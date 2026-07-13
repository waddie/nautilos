# nautilos: evaluate code in a live nREPL server

Use `nautilos` when a project runs an [nREPL](https://nrepl.org) server (Clojure,
ClojureScript, Babashka, Janet, Steel, basilisp) and you want to evaluate forms,
inspect symbols, complete prefixes, or load files in the running runtime instead
of restarting a process per step. REPL state (defs, imports) persists across
calls, so do not re-establish prior state on each call.

There are two ways to drive it; pick whichever your harness has wired up.

## As MCP tools (preferred)

If `nautilos` is registered as an MCP server, you get tools: `eval`, `lookup`,
`complete`, `load_file`, `describe`, `interrupt`, `stdin`, `ls_sessions`,
`session`. The server holds one session for the whole session, so
`eval {"code":"(def x 1)"}` then `eval {"code":"(inc x)"}` returns `2`. Each
tool returns the nREPL result as JSON text; read `status` for success vs error.
To work in a session that already exists on the server, find its id with
`ls_sessions` and attach with `session {"id":"..."}`.

## As a CLI

```
nautilos eval '(def x 41)'     # auto-starts a daemon that holds the session
nautilos eval '(+ x 1)'        # => value "42": state persisted across processes
nautilos lookup map
nautilos complete map-
nautilos load-file path/to/file
nautilos describe
nautilos ls-sessions           # ids of every session on the server
nautilos session <id>          # attach to one; later commands run there
nautilos interrupt
nautilos down
```

The daemon is keyed by the working directory, so run commands from the project
directory. Every command prints one JSON object.

## Code that reads input

Evaluated code that reads input (`read-line`, `getline`) blocks until input
arrives over nREPL. Prefer pre-supplying it with the eval:
`nautilos eval '(read-line)' --input hi` (MCP: the eval tool's `input`
parameter). If an eval hangs, `nautilos status` reporting `need-input: true`
means it awaits input: answer with `nautilos stdin "text"` from another shell
(or the `stdin` tool), or send end-of-input with `nautilos stdin` (no text).
Reserve `interrupt` for actual runaway evals.

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
`load-file`; `lookup`, `complete`, `interrupt`, and `stdin` vary by server
(babashka lacks `stdin`), so run `describe` first when unsure what a server
supports.
