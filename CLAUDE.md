# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

An agent-facing nREPL tool, packaged as a Claude Code plugin. A Janet daemon
holds one nREPL connection and one cloned session for a whole task; a thin Janet
CLI issues one command per process over a unix socket and prints JSON. It lets an
agent drive any nREPL server (Clojure, babashka, Janet, Steel, basilisp) while
REPL state accrues across calls.

## Why the daemon exists

The servers we target scope a session to its connection: reconnecting starts an
empty session. Agents run a tool once per shell command, so without a persistent
holder every eval would lose prior defs. The daemon is that holder. It is keyed
by project directory (hash of the realpath) so multiple projects coexist.

## Architecture

```
CLI path: agent -> nautilos CLI -(unix socket, NDJSON)-> daemon -\
MCP path: agent -> nautilos mcp  -(JSON-RPC 2.0, stdio) ---------- }-> held conn -> nREPL server
                                                                     one cloned session
                                                                     id-demux router (nrepl-janet)
```

Two front-ends over one multiplexing nREPL client. The CLI path uses a separate
daemon process (the CLI is short-lived); the MCP path is itself long-lived, so it
holds the session directly with no daemon.

- `src/main.janet`: parses `nautilos <cmd> [args] [--host H] [--port P]`. `mcp`
  runs the MCP server; `daemon` runs the CLI daemon (both blocking); every other
  subcommand is a client call that auto-starts the daemon.
- `src/daemon.janet`: connects via the multiplexing client, clones a session,
  serves CLI requests on a unix socket. `net/accept-loop` runs each handler in
  its own fiber, so an `interrupt` is processed while an `eval` is still in
  flight; their responses are routed apart by request id.
- `src/mcp.janet`: JSON-RPC 2.0 over stdio. stdin is read on a dedicated OS
  thread feeding a threaded channel, because a blocking read on the main thread
  monopolises the event loop (Janet `ev/read` on a pipe waits without yielding)
  and would stall the client's reader fiber. Each request is handled in its own
  fiber, preserving interrupt-while-eval. Holds the session for the process life.
- `src/cli.janet`: liveness-checks the socket, auto-starts a fully detached
  daemon with `nohup <self> daemon ... &`, sends one request, prints the result.
- `src/discovery.janet`: `.nrepl-port` lookup and per-project socket/log paths.
  The runtime dir is `NAUTILOS_RUNTIME_DIR`, else `XDG_RUNTIME_DIR`, else a
  per-user 0700 dir under `/tmp` (shared `/tmp` invites symlink and socket-squat
  attacks). Socket paths are kept short because unix paths are length-limited
  (~104 bytes on macOS).
- `src/ipc.janet`: one newline-delimited JSON object each way per connection.

## Dependency

The real nREPL client lives in `nrepl-janet` as `nrepl/client` (the multiplexing
layer: per-request `:id`, a reader fiber routing responses to per-id channels,
merged results, write lock, `interrupt`, `.nrepl-port` discovery). Anything
useful to any client author belongs there, not here. `project.janet` pins the
git dependency; the published library must include that client layer.

## Build and verify

```sh
jpm deps
jpm quickbin src/main.janet bin/nautilos-darwin-arm64   # ~800 KB, libSystem only
```

Verify against a live server (state must persist across two processes):

```sh
janet -e '(import nrepl)(nrepl/run-server "127.0.0.1" 17000)' &
nautilos eval '(def x 41)' --port 17000      # value "41"
nautilos eval '(+ x 1)' --port 17000         # value "42", same session
```

Repeat against `bb nrepl-server <port>` and `steel nrepl-steel.scm host:port` to
confirm the client spans ecosystems. For the MCP path, set `NAUTILOS_PORT` and
speak JSON-RPC to `nautilos mcp` (initialize, tools/list, tools/call).

## Gotchas

- Concurrent socket writes from two fibers would corrupt bencode frames; the
  multiplexing client serialises writes through a capacity-1 channel used as a
  lock. Keep that invariant if touching the client.
- The daemon tears down when the upstream connection drops; the next CLI call
  auto-starts a fresh one. Do not assume a daemon outlives its server.
- Portable ops: `eval`, `clone`, `describe`, `load-file`. `lookup`, `complete`,
  `interrupt`, `stdin` vary per server (babashka lacks `stdin`). Prefer
  `describe` to gate optional ops.
- Code that reads input blocks on a `need-input` status until a `stdin` op
  arrives. Pre-supplied input (`eval --input`) is sent ahead of the eval and
  buffered by the server; unconsumed input feeds the session's next read.
