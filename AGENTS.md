# nautilos: evaluate code in a live nREPL server

Use `nautilos` when a project runs an [nREPL](https://nrepl.org) server (Clojure,
ClojureScript, Babashka, Janet, Steel, basilisp) and you want to evaluate forms,
inspect symbols, complete prefixes, or load files in the running runtime instead
of restarting a process per step. REPL state (defs, imports) persists across
calls, so do not re-establish prior state on each call.

There are two ways to drive it; pick whichever your harness has wired up.

## As MCP tools (preferred)

If `nautilos` is registered as an MCP server, you get tools: `eval`, `lookup`,
`complete`, `load_file`, `describe`, `interrupt`, `ls_sessions`. The server holds
one session for the whole session, so `eval {"code":"(def x 1)"}` then
`eval {"code":"(inc x)"}` returns `2`. Each tool returns the nREPL result as
JSON text; read `status` for success vs error.

## As a CLI

```
nautilos eval '(def x 41)'     # auto-starts a daemon that holds the session
nautilos eval '(+ x 1)'        # => value "42": state persisted across processes
nautilos lookup map
nautilos complete map-
nautilos load-file path/to/file
nautilos describe
nautilos interrupt
nautilos down
```

The daemon is keyed by the working directory, so run commands from the project
directory. Every command prints one JSON object.

## Prerequisite and configuration

`nautilos` is a client; the project must already run an nREPL server, started
with whatever suits the language, for example `bb nrepl-server <port>` (babashka)
or `janet -e '(import nrepl)(nrepl/run-server "127.0.0.1" <port>)'` (Janet).

The port is found from a `.nrepl-port` file in the project root when present.
Otherwise set it: `--port <n>` for the CLI, or `NAUTILOS_PORT` (and
`NAUTILOS_HOST`) in the environment for the MCP server.

## Output shape

Eval results carry `value` and `values`, `out`/`err`, `status` (`["done"]`,
`["eval-error","done"]`, `["interrupted","done"]`), `session`, `ns`, and on error
`ex`/`root-ex`. `lookup`/`complete`/`describe`/`ls-sessions` add `info`,
`completions`, `ops`/`versions`, `sessions`. Portable ops are `eval`, `describe`,
`load-file`; `lookup`, `complete`, and `interrupt` vary by server, so run
`describe` first when unsure what a server supports.
