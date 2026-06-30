###
### daemon.janet
###
### Holds one persistent nREPL connection and one cloned session for the whole
### coding session, and serves short-lived CLI commands over a unix socket. The
### connection must stay open because these servers (nrepl-janet, nrepl-steel)
### scope sessions to the connection: reconnecting drops accrued REPL state.
###
### `net/accept-loop` runs each client handler in its own fiber, so an
### `interrupt` command can be processed while an `eval` command is still in
### flight on another fiber; the multiplexing client routes their responses
### apart by request id.

(import nrepl/client :as nc)
(import ./ipc)
(import ./discovery)

(defn- eval-opts
  [req]
  (def o @{})
  (when-let [f (get req "file")] (put o :file f))
  (when-let [l (get req "line")] (put o :line l))
  (when-let [c (get req "column")] (put o :column c))
  o)

(defn- load-opts
  [req]
  (def o @{})
  (when-let [n (get req "file-name")] (put o :file-name n))
  (when-let [p (get req "file-path")] (put o :file-path p))
  o)

(defn- with-session
  "Ensure the result carries the daemon's session id for context."
  [r session]
  (put r :session (or (get r :session) session))
  r)

(defn- process
  "Translate one CLI request into nREPL ops over the held connection and return
  a JSON-friendly result table."
  [req state]
  (def conn (in state :conn))
  (def session (in state :session))
  (case (get req "op")
    "eval"
    (do
      (put state :busy true)
      (def r (nc/eval-code conn session (get req "code" "") (eval-opts req)))
      (put state :busy false)
      (with-session r session))

    "load-file"
    (with-session
      (nc/load-file-code conn session (get req "contents" "") (load-opts req))
      session)

    "lookup" (with-session (nc/lookup conn session (get req "sym" "")) session)
    "complete" (with-session (nc/completions conn session (get req "prefix" "")) session)
    "describe" (with-session (nc/describe conn) session)
    "ls-sessions" (with-session (nc/ls-sessions conn) session)

    # No interrupt-id: the server cancels whatever eval is running on the session.
    "interrupt" (with-session (nc/call conn {:op "interrupt" :session session}) session)

    "status" @{:ok true :session session :host (in state :host)
               :port (in state :port) :busy (in state :busy)}

    "shutdown" (do (put state :shutdown true) @{:ok true})

    @{:error (string "unknown op: " (get req "op"))}))

(defn run
  "Connect to the nREPL server at `host`:`port`, clone a session, and serve CLI
  commands on the project's unix socket until a `shutdown` command arrives or the
  server connection drops. Blocks."
  [&named host port]
  (default host "127.0.0.1")
  (def sock (discovery/sock-path))
  # Clear any stale socket file left by a previous daemon (the caller is expected
  # to have checked that no live daemon owns it).
  (when (os/stat sock :mode) (os/rm sock))

  (def conn (nc/connect-mux host port))
  (def clone-res (nc/clone-session conn))
  (def session (string (get clone-res :new-session)))
  (unless (get clone-res :new-session)
    (error "nREPL server did not return a session on clone"))

  (def state @{:conn conn :session session :host host :port port
               :busy false :shutdown false})

  (def listener (net/listen :unix sock))
  (defer (do
           (protect (:close listener))
           (when (os/stat sock :mode) (os/rm sock))
           (nc/close-mux conn))
    (net/accept-loop listener
                     (fn [stream]
                       (defer (protect (:close stream))
                         (def req (ipc/read-msg stream))
                         (when req
                           (ipc/write-msg stream (process req state))
                           # End the accept loop on an explicit shutdown, or if the upstream
                           # nREPL connection has dropped (the next CLI call then starts fresh).
                           (when (or (in state :shutdown) (get (in state :conn) :closed))
                             (protect (:close listener)))))))))
