###
### cli.janet
###
### The thin client side: locate (and if needed auto-start) the daemon, send it
### one command over the unix socket, and print the JSON response. Designed for
### an agent to call once per shell command.

(import spork/json :as json)
(import ./ipc)
(import ./discovery)

(defn- shell-quote
  [s]
  (string "'" (string/replace-all "'" `'\''` (string s)) "'"))

(defn- self-exe
  "Path to this program as invoked, used to re-exec the daemon subcommand."
  []
  (first (dyn :args)))

(defn alive?
  "True if a daemon is listening on the project's socket."
  []
  (def sock (discovery/sock-path))
  (and (truthy? (os/stat sock :mode))
       (try
         (do (def s (net/connect :unix sock)) (:close s) true)
         ([_] false))))

(defn- start-daemon
  "Spawn a fully detached daemon (via `nohup ... &`) and wait for its socket."
  [host port]
  (def sock (discovery/sock-path))
  (def log (discovery/log-path))
  (def cmd (string/format "nohup %s daemon --host %s --port %s >%s 2>&1 &"
                          (shell-quote (self-exe))
                          (shell-quote host)
                          (shell-quote (string port))
                          (shell-quote log)))
  (os/execute ["sh" "-c" cmd] :p)
  (var ok false)
  (for _ 0 100
    (when (alive?) (set ok true) (break))
    (os/sleep 0.05))
  (unless ok (errorf "daemon failed to start; see %s" log)))

(defn ensure
  "Make sure a daemon is running for this project, starting one if necessary.
  Resolves the nREPL port from `port` or a `.nrepl-port` file only when a start
  is actually needed."
  [&named host port]
  (default host "127.0.0.1")
  (unless (alive?)
    (def sock (discovery/sock-path))
    (when (os/stat sock :mode) (os/rm sock)) # clear stale socket file
    (start-daemon host (discovery/resolve-port port))))

(defn send-op
  "Send one request to the daemon and return its decoded response."
  [req]
  (def s (net/connect :unix (discovery/sock-path)))
  (defer (:close s)
    (ipc/write-msg s req)
    (or (ipc/read-msg s) @{:error "no response from daemon"})))

(defn print-json
  [data]
  (print (json/encode data)))

(defn down
  "Shut the daemon down if it is running."
  []
  (if (alive?)
    (print-json (send-op {:op "shutdown"}))
    (print-json @{:ok true :running false})))
