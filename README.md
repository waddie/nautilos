# Nautilos

An agent-facing nREPL tool. A small native daemon plus a thin CLI let an agent
evaluate code in any [nREPL](https://nrepl.org) server and keep accrued REPL
state across calls.

Written in Janet for small, native binaries with no runtime requirement.

## Why a daemon

Agents invoke a tool once per shell command, so the process exits between calls.
Some servers scope a session to its connection (reconnecting drops accrued
state), and re-establishing state on every eval is slow and token-expensive. So a
long-lived daemon holds one connection and one cloned session for the whole task;
the CLI issues one command per invocation over a unix socket. The daemon is keyed
by the project directory, so separate projects get separate sessions.

## Install

Both paths put a `nautilos` binary on your PATH for the CLI and MCP surfaces. The
Claude Code plugin path is separate and needs no install (it bundles its own
binary selector).

curl:

```sh
curl -fsSL https://raw.githubusercontent.com/waddie/nautilos/main/install.sh | sh
```

Installs to `~/.local/bin` by default. Override with `NAUTILOS_BIN_DIR`, or pin a
release with `NAUTILOS_VERSION`:

```sh
NAUTILOS_BIN_DIR=/usr/local/bin NAUTILOS_VERSION=v0.3.0 \
  curl -fsSL https://raw.githubusercontent.com/waddie/nautilos/main/install.sh | sh
```

npm:

```sh
npm install -g @waddie/nautilos
```

The right binary for your OS/arch is selected via optional dependencies, so there
are no install scripts. Prebuilt binaries cover darwin and linux on arm64 and x64;
Linux builds are glibc-linked (not musl/Alpine). Otherwise build from source (see
[Build](#build)).

## Use

A project must already run an nREPL server (started however suits the language).
Then, from the project directory:

```sh
nautilos eval '(def x 41)'     # auto-starts the daemon
nautilos eval '(+ x 1)'        # => value "42": state persisted across processes
nautilos lookup map
nautilos complete map-
nautilos describe
nautilos interrupt
nautilos down
```

Code that reads input takes it via the nREPL `stdin` op. Pre-supply it with the
eval, or answer a blocked eval from another shell:

```sh
nautilos eval '(read-line)' --input hi   # buffered ahead: completes at once
nautilos eval '(read-line)' &            # blocks; status shows need-input true
nautilos stdin "hi"                      # unblocks it; bare `nautilos stdin` sends end-of-input
```

The port comes from a `.nrepl-port` file when present, or `--port <n>`. Every
command prints one JSON object; read `status` for success or error. See
[`skills/nautilos/SKILL.md`](skills/nautilos/SKILL.md) for the full command and
output reference.

## Use with agent harnesses

The same binary serves three integration surfaces over one held session.

- **Claude Code**: the bundled plugin (`.claude-plugin/plugin.json` +
  `skills/nautilos`). Install from this repo’s own marketplace:

  ```
  /plugin marketplace add waddie/nautilos
  /plugin install nautilos@nautilos
  ```

- **MCP** (Codex, opencode, Cursor, Zed, Claude Code, ...): run `nautilos mcp`, a
  JSON-RPC 2.0 stdio server exposing `eval`, `lookup`, `complete`, `load_file`,
  `describe`, `interrupt`, `stdin`, `ls_sessions` as tools. Because the MCP process is
  long-lived, it holds the session directly; no daemon is involved on this path.
- **Prose** (`AGENTS.md`): for harnesses that read instructions rather than
  register tools.

Register the MCP server with one line. The port comes from `.nrepl-port` or the
`NAUTILOS_PORT` env var.

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.nautilos]
command = "nautilos"
args = ["mcp"]
```

opencode (`opencode.json`):

```json
{
  "mcp": {
    "nautilos": {
      "type": "local",
      "command": ["nautilos", "mcp"],
      "enabled": true
    }
  }
}
```

Claude Code (`.mcp.json`):

```json
{ "mcpServers": { "nautilos": { "command": "nautilos", "args": ["mcp"] } } }
```

## Build

```sh
jpm deps # fetch spork + nrepl-janet
jpm quickbin src/main.janet bin/nautilos-darwin-arm64
```

The multiplexing nREPL client this depends on lives in `nrepl-janet`
(`nrepl/client`). Prebuilt binaries for darwin and linux on arm64 and x64 are
produced by the `build` workflow on each native runner; the wrapper at
`skills/nautilos/scripts/nautilos` selects the right one by `uname`.

## License

Copyright © 2026 Tom Waddington

Distributed under the MIT License. See LICENSE file for details.
