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
(import ./opts)

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
      # defer, not sequential puts: an eval that throws must not leave the
      # daemon reporting busy forever.
      (defer (put state :busy false)
        # Pre-supplied input is sent ahead of the eval; the server buffers it,
        # so code that reads input completes without a need-input round trip.
        (when-let [input (get req "input")]
          (nc/send-stdin conn session (opts/stdin-input input)))
        (with-session
          (nc/eval-code conn session (get req "code" "") (opts/eval-opts req))
          session)))

    "load-file"
    (with-session
      (nc/load-file-code conn session (get req "contents" "") (opts/load-opts req))
      session)

    "lookup" (with-session (nc/lookup conn session (get req "sym" "")) session)
    "complete" (with-session (nc/completions conn session (get req "prefix" "")) session)
    "describe" (with-session (nc/describe conn) session)
    "ls-sessions" (with-session (nc/ls-sessions conn) session)

    # No interrupt-id: the server cancels whatever eval is running on the session.
    "interrupt" (with-session (nc/call conn {:op "interrupt" :session session}) session)

    # Answers an eval blocked on need-input, or buffers input ahead of demand.
    # An empty payload signals end-of-input.
    "stdin"
    (with-session (nc/send-stdin conn session (opts/stdin-input (get req "input" "")))
      session)

    "status" @{:ok true :session session :host (in state :host)
               :port (in state :port) :busy (in state :busy)
               # True when the in-flight eval is blocked awaiting a `stdin` op
               # (distinguishes a stdin-wait from a slow computation).
               :need-input (truthy? (get conn :need-input))}

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
                           # A dead upstream connection must be caught up front: a
                           # write on it can succeed silently (first write after peer
                           # death) with the reader fiber already gone, so the op
                           # would block forever awaiting responses. And a throw from
                           # an op must still produce a response and still reach the
                           # teardown check below; otherwise the daemon lingers on
                           # the socket and every later call fails.
                           (def res
                             (cond
                               (get (in state :conn) :closed)
                               @{:error "nREPL server connection closed; daemon shutting down, retry to start fresh"}

                               (try (process req state)
                                 ([err] @{:error (if (string? err) err (describe err))}))))
                           (protect (ipc/write-msg stream res))
                           # End the accept loop on an explicit shutdown, or if the upstream
                           # nREPL connection has dropped (the next CLI call then starts fresh).
                           (when (or (in state :shutdown) (get (in state :conn) :closed))
                             (protect (:close listener)))))))))
