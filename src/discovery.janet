###
### discovery.janet
###
### Locating things: the nREPL server port (via the `.nrepl-port` convention)
### and the per-project paths for the daemon's unix socket and log. The socket is
### keyed by the project directory so multiple projects/servers coexist, and the
### path is kept short (unix socket paths are length-limited, ~104 bytes on
### macOS) by hashing the directory rather than embedding it.

(import nrepl/client :as nc)

(defn- runtime-dir
  []
  (or (os/getenv "NAUTILOS_RUNTIME_DIR") "/tmp"))

(defn project-key
  "Stable short key for `dir` (defaults to cwd). `hash` is deterministic across
  processes, so the same directory always yields the same key."
  [&opt dir]
  (default dir (os/cwd))
  (string/format "%x" (math/abs (hash (os/realpath dir)))))

(defn sock-path
  "Unix socket path the daemon for `dir` listens on."
  [&opt dir]
  (string (runtime-dir) "/nautilos-nrepl-" (project-key dir) ".sock"))

(defn log-path
  "Log file the detached daemon for `dir` writes to."
  [&opt dir]
  (string (runtime-dir) "/nautilos-nrepl-" (project-key dir) ".log"))

(defn resolve-port
  "Resolve the nREPL server port: explicit `port` if given, else a `.nrepl-port`
  found in the cwd or an ancestor. Errors if neither is available."
  [port]
  (or port
      (nc/find-nrepl-port)
      (error "no nREPL port: pass --port or create a .nrepl-port file")))
