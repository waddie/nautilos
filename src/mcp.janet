###
### mcp.janet
###
### An MCP (Model Context Protocol) server over stdio, so any MCP-capable harness
### (Codex, opencode, Claude Code, Cursor, …) can drive an nREPL server through
### typed tools with one config line.
###
### The server is a long-lived process for the whole agent session, so it *is*
### the session holder: it connects to the nREPL server once, clones one session,
### and keeps it for its lifetime. No separate daemon is needed on this path.
###
### Transport is newline-delimited JSON-RPC 2.0. A blocking read on stdin would
### monopolise the single-threaded event loop (Janet's `ev/read` on a pipe waits
### without yielding), which would stall the multiplexing client's reader fiber.
### So stdin is read on a dedicated OS thread that feeds lines to the main loop
### over a threaded channel, keeping the loop free: the client's reader fiber
### stays live and an `interrupt` tool call can be handled while an `eval` is
### still in flight. stdout is written through an async stream under a lock.
### Diagnostics go to stderr; stdout carries only protocol messages.

(import spork/json :as json)
(import nrepl/client :as nc)
(import ./discovery)
(import ./opts)

# Newest first: the reply to a request for an unsupported version. All three
# are equivalent for a tools-only stdio server (no batching, no audio, no
# elicitation).
(def- supported-protocol-versions ["2025-06-18" "2025-03-26" "2024-11-05"])
# Keep in sync with project.janet; the release workflow checks they agree.
(def- server-version "0.2.2")

(defn- log [& xs] (eprint ;xs))

# --- stdin reader thread ----------------------------------------------------

(defn- stdin-reader
  "Runs on its own OS thread: blocking-read stdin line by line onto `chan`,
  pushing `:eof` when the stream ends. Must stay free of closures over
  non-marshallable state so it can cross the thread boundary."
  [chan]
  (forever
    (def line (file/read stdin :line))
    (when (nil? line) (ev/give chan :eof) (break))
    (ev/give chan (string line))))

# --- framing ----------------------------------------------------------------

(defn- write-msg
  "Serialise `data` as JSON and write it newline-delimited to the output stream,
  serialised through the write lock so concurrent handler fibers can't interleave."
  [state data]
  (def wlock (in state :wlock))
  (ev/take wlock)
  (defer (ev/give wlock :token)
    (ev/write (in state :out) (buffer (json/encode data) "\n"))))

(defn- respond [state id result]
  (write-msg state {:jsonrpc "2.0" :id id :result result}))

(defn- respond-error [state id code message]
  (write-msg state {:jsonrpc "2.0" :id id :error {:code code :message message}}))

# --- connection (the MCP process holds one session) -------------------------

(defn- ensure-conn
  "Connect and clone a session on first use, or after the connection dropped.
  Port comes from NAUTILOS_PORT or a .nrepl-port file; host from NAUTILOS_HOST.
  Serialised through `:conn-lock`: connect and clone yield, so two tool-call
  fibers racing here would otherwise both connect and leak one connection."
  [state]
  (def lock (in state :conn-lock))
  (ev/take lock)
  (defer (ev/give lock :token)
    (when (or (nil? (in state :conn)) (get (in state :conn) :closed))
      (def host (or (os/getenv "NAUTILOS_HOST") "127.0.0.1"))
      (def port (discovery/resolve-port (os/getenv "NAUTILOS_PORT")))
      (def conn (nc/connect-mux host port))
      (def r (nc/clone-session conn))
      (unless (get r :new-session)
        (nc/close-mux conn)
        (error "nREPL server did not return a session on clone"))
      (put state :conn conn)
      (put state :session (string (get r :new-session)))))
  state)

# --- tools ------------------------------------------------------------------

(def- tool-defs
  [{:name "eval"
    :description "Evaluate code in the held nREPL session. State (defs, imports) persists across calls."
    :inputSchema {:type "object"
                  :properties {:code {:type "string" :description "Code to evaluate."}
                               :file {:type "string"}
                               :line {:type "integer"}
                               :column {:type "integer"}}
                  :required ["code"]}}
   {:name "lookup"
    :description "Doc, arglists, and source location for a symbol."
    :inputSchema {:type "object"
                  :properties {:sym {:type "string"}}
                  :required ["sym"]}}
   {:name "complete"
    :description "Completion candidates for a prefix in the session."
    :inputSchema {:type "object"
                  :properties {:prefix {:type "string"}}
                  :required ["prefix"]}}
   {:name "load_file"
    :description "Evaluate the contents of a file at `path`, using its name for error locations."
    :inputSchema {:type "object"
                  :properties {:path {:type "string"}}
                  :required ["path"]}}
   {:name "describe"
    :description "Ops and versions the nREPL server advertises. Use to gate optional ops."
    :inputSchema {:type "object" :properties {}}}
   {:name "interrupt"
    :description "Cancel the eval currently running on the session."
    :inputSchema {:type "object" :properties {}}}
   {:name "ls_sessions"
    :description "List active sessions on the nREPL server."
    :inputSchema {:type "object" :properties {}}}])

(defn- run-tool
  [state name args]
  (ensure-conn state)
  (def conn (in state :conn))
  (def session (in state :session))
  (case name
    "eval" (nc/eval-code conn session (get args "code" "") (opts/eval-opts args))
    "lookup" (nc/lookup conn session (get args "sym" ""))
    "complete" (nc/completions conn session (get args "prefix" ""))
    "load_file" (let [p (get args "path")]
                  (nc/load-file-code conn session (string (slurp p))
                                     {:file-name (last (string/split "/" p)) :file-path p}))
    "describe" (nc/describe conn)
    "interrupt" (nc/call conn {:op "interrupt" :session session})
    "ls_sessions" (nc/ls-sessions conn)
    (errorf "unknown tool: %s" name)))

(defn- errored?
  [r]
  (when-let [st (get r :status)]
    (some (fn [s] (or (= "error" s) (= "eval-error" s))) st)))

(defn- tool-result
  "Wrap a merged nREPL result as MCP tool content (the JSON as text)."
  [r]
  {:content [{:type "text" :text (json/encode r)}] :isError (truthy? (errored? r))})

# --- dispatch ---------------------------------------------------------------

(defn- handle
  [msg state]
  (def id (get msg "id"))
  (def method (get msg "method"))
  (def params (get msg "params" {}))
  (cond
    (= method "initialize")
    # Echo the client's version only when we support it; otherwise answer with
    # our newest so the client can decide (echoing blindly claims support for
    # anything).
    (let [pv (get params "protocolVersion")
          negotiated (if (index-of pv supported-protocol-versions)
                       pv
                       (first supported-protocol-versions))]
      (respond state id {:protocolVersion negotiated
                         :capabilities {:tools {}}
                         :serverInfo {:name "nautilos" :version server-version}}))

    (= method "notifications/initialized") nil # notification: no reply

    (= method "ping") (respond state id {})

    (= method "tools/list") (respond state id {:tools tool-defs})

    (= method "tools/call")
    (try
      (respond state id (tool-result (run-tool state (get params "name") (get params "arguments" {}))))
      ([err]
        # Tool failures (e.g. no server reachable) are reported as tool results,
        # not protocol errors, so the agent sees an actionable message.
        (respond state id {:content [{:type "text" :text (string "error: " err)}] :isError true})))

    # Unknown method: error for requests, silence for notifications.
    (truthy? id) (respond-error state id -32601 (string "method not found: " method))))

(defn run
  "Run the MCP stdio server loop. Blocks until stdin closes."
  [&]
  (def state @{:wlock (ev/chan 1)
               :conn-lock (ev/chan 1)
               :inflight 0
               :out (os/open "/dev/stdout" :w)})
  (ev/give (in state :wlock) :token)
  (ev/give (in state :conn-lock) :token)
  (def lines (ev/thread-chan 32))
  (ev/thread stdin-reader lines :n)
  (forever
    (def line (ev/take lines))
    (if (= line :eof) (break))
    (unless (empty? (string/trim line))
      (def msg (try (json/decode line) ([_] (do (log "ignoring unparseable line") nil))))
      # Each request in its own fiber, so an interrupt can overlap an eval.
      # Counted so shutdown below can drain them: fibers don't yield between
      # the increment and the spawn, so the counter is race-free.
      (when msg
        (put state :inflight (+ 1 (in state :inflight)))
        (ev/spawn
          (defer (put state :inflight (- (in state :inflight) 1))
            (handle msg state))))))
  # stdin closed: the client is done with us. Wait briefly for in-flight
  # handlers (one may still be creating the connection), then close the held
  # connection so its reader fiber ends; otherwise the event loop never drains
  # and the process outlives its client. A handler still blocked on an eval
  # after the grace period is unblocked by the close itself.
  (var waited 0)
  (while (and (pos? (in state :inflight)) (< waited 5))
    (ev/sleep 0.05)
    (+= waited 0.05))
  (when-let [conn (in state :conn)]
    (protect (nc/close-mux conn))))
