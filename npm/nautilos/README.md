# @waddie/nautilos

An agent-facing nREPL tool. A small native daemon plus a thin CLI let an agent
evaluate code in any [nREPL](https://nrepl.org) server (Clojure, babashka, Janet,
Steel, basilisp, ...) and keep accrued REPL state across calls.

Written in Janet for small, native binaries with no runtime requirement.

## Install

```sh
npm install -g @waddie/nautilos
```

The binary for your OS/arch is selected via optional dependencies, so there are no
install scripts. Prebuilt binaries cover darwin and linux on arm64 and x64; Linux
builds are glibc-linked (not musl/Alpine).

## Use

From a project directory that already runs an nREPL server:

```sh
nautilos eval '(def x 41)'     # auto-starts the daemon
nautilos eval '(+ x 1)'        # => value "42": state persisted across processes
nautilos describe
nautilos down
```

The port comes from a `.nrepl-port` file when present, or `--port <n>`. Every
command prints one JSON object; read `status` for success or error.

`nautilos mcp` runs a JSON-RPC 2.0 stdio MCP server exposing the same operations
as tools, for harnesses that register MCP servers.

See the [project README](https://github.com/waddie/nautilos) for the full command
and output reference, MCP registration, and agent-harness integration.

## License

MIT. Copyright © 2026 Tom Waddington.
