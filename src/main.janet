###
### main.janet
###
### Entry point. Parses `nrepl <subcommand> [args] [--host H] [--port P]` and
### dispatches to the daemon (the long-lived `daemon` subcommand) or the client
### (every other subcommand, which auto-starts the daemon as needed).

(import spork/json :as json)
(import ./cli)
(import ./daemon)
(import ./mcp)
(import ./discovery)

(defn- parse
  "Split args into a `--flag value` table and an array of positionals."
  [args]
  (def flags @{})
  (def pos @[])
  (var i 0)
  (while (< i (length args))
    (def a (in args i))
    (if (string/has-prefix? "--" a)
      (do (put flags (string/slice a 2) (get args (+ i 1))) (+= i 2))
      (do (array/push pos a) (++ i))))
  [flags pos])

(defn- read-code
  "Code to evaluate: the first positional, or all of stdin when it is absent or
  `-` (lets an agent pipe in a multi-line form)."
  [pos]
  (def a (first pos))
  (if (or (nil? a) (= a "-"))
    (string (file/read stdin :all))
    a))

(defn- usage
  []
  (eprint "usage: nrepl <command> [args] [--host H] [--port P]")
  (eprint "commands: eval lookup complete load-file describe ls-sessions interrupt up down status daemon mcp"))

(defn main
  [&]
  (def args (drop 1 (dyn :args)))
  (def cmd (first args))
  (def [flags pos] (parse (drop 1 args)))
  (def host (get flags "host" "127.0.0.1"))
  (def port (get flags "port"))

  (defn client-op [req]
    (cli/ensure :host host :port port)
    (cli/print-json (cli/send-op req)))

  (case cmd
    "mcp" (mcp/run)
    "daemon" (daemon/run :host host :port (discovery/resolve-port port))
    "up" (do (cli/ensure :host host :port port)
           (cli/print-json @{:ok true :socket (discovery/sock-path)}))
    "down" (cli/down)
    "status" (cli/print-json (if (cli/alive?)
                               (cli/send-op {:op "status"})
                               @{:ok true :running false}))
    "eval" (client-op {:op "eval" :code (read-code pos)})
    "lookup" (client-op {:op "lookup" :sym (first pos)})
    "complete" (client-op {:op "complete" :prefix (or (first pos) "")})
    "describe" (client-op {:op "describe"})
    "ls-sessions" (client-op {:op "ls-sessions"})
    "interrupt" (client-op {:op "interrupt"})
    "load-file" (let [path (first pos)]
                  (client-op {:op "load-file"
                              :contents (string (slurp path))
                              :file-name (last (string/split "/" path))
                              :file-path path}))
    (do (usage) (os/exit 1))))
