---
name: nautilos
description: Evaluate code in a live nREPL server and keep REPL state across calls. Use when a project runs an nREPL server (Clojure, ClojureScript, babashka, Janet, Steel, basilisp) and you want to evaluate forms, inspect symbols, complete prefixes, or load files in a running runtime rather than restarting a process per step.
---

# nautilos

Drive any nREPL server from the shell. A background daemon holds one connection
and one session for the whole task, so definitions and imports persist between
calls. A thin CLI issues one command per invocation and prints a JSON result.

The command is the wrapper:

```sh
NREPL="$CLAUDE_PLUGIN_ROOT/skills/nautilos/scripts/nautilos"
```

It selects the prebuilt binary for this OS/arch. If none matches, it prints a
JSON error naming the expected path and the `jpm quickbin` build command; report
that and stop rather than guessing.

## Prerequisite: a running nREPL server

The skill is a client. The project must already run an nREPL server, started
with whatever command suits the language, for example:

- Clojure: a `clj`/Leiningen jack-in, or `bb nrepl-server <port>` for babashka
- Janet: `janet -e '(import nrepl)(nrepl/run-server "127.0.0.1" <port>)'`
- Steel: `steel nrepl-steel.scm 127.0.0.1:<port>`

Most tooling writes a `.nrepl-port` file in the project root. When it exists the
CLI finds the port itself. Otherwise pass `--port <n>` (and `--host` if not
`127.0.0.1`).

## Commands

`$NREPL <command> [args] [--port N] [--host H]`

| Command                  | Use                                                                              |
| ------------------------ | -------------------------------------------------------------------------------- |
| `eval '<code>'`          | Evaluate code (or pass `-` to read the form from stdin). Auto-starts the daemon. |
| `lookup <sym>`           | Doc, arglists, source location for a symbol.                                     |
| `complete <prefix>`      | Completion candidates for a prefix.                                              |
| `load-file <path>`       | Evaluate a file's contents with its name for error locations.                    |
| `describe`               | Ops and versions the server advertises.                                          |
| `ls-sessions`            | Active sessions on the server.                                                   |
| `interrupt`              | Cancel the eval currently running on the session.                                |
| `stdin [text]`           | Deliver input to an eval blocked on reading; no text signals end-of-input.       |
| `up` / `down` / `status` | Start, stop, or query the daemon for this project.                               |

The daemon is keyed by the current directory, so separate projects (or servers
on different ports) get separate daemons and sessions. Run commands from the
project directory.

## Output

Every command prints one JSON object. Eval-shaped results carry:

- `value` (last form's value) and `values` (one per form)
- `out`, `err` (captured stdout/stderr)
- `status` (e.g. `["done"]`, `["eval-error","done"]`, `["interrupted","done"]`)
- `session`, `ns`
- on error: `ex` / `root-ex`

`lookup`, `complete`, `describe`, `ls-sessions` add `info`, `completions`,
`ops`/`versions`, `sessions` respectively. Read `status` to tell success from an
error; the eval still returns even when it errors.

## Code that reads input

Evaluated code that reads input (`read-line` in Clojure, `getline` in Janet)
blocks until input arrives over nREPL, not from any terminal. Two ways to
supply it:

- **Pre-supply (preferred)**: when the code is known to read input, pass it with
  the eval: `$NREPL eval '(read-line)' --input hi`. The server buffers it, so
  the call completes in one step. A trailing newline is added if missing.
  Input the code does not consume stays buffered and feeds the next read.
- **Answer a blocked eval**: if an eval hangs, run `$NREPL status` from another
  shell. `need-input: true` means it is waiting for input, not stuck: send
  `$NREPL stdin "text"` to answer it, or `$NREPL stdin` (no text) for
  end-of-input. Reserve `interrupt` for actual runaway evals.

## State persists

Definitions accrue. `$NREPL eval '(def x 1)'` then `$NREPL eval '(inc x)'` in a
later call returns `2`: the daemon kept the session alive between the two
processes. Do not re-establish prior state on each call.

## Lifecycle and portability

- `eval` (and the other client commands) start the daemon on first use; you do
  not normally call `up`.
- `down` when finished, or leave it: it is cheap and exits if the server
  connection drops.
- Portable ops are `eval`, `clone`, `describe`, `load-file`. `lookup`,
  `complete`, `interrupt`, and `stdin` semantics vary by server (babashka lacks
  `stdin`); if a server lacks one its `status` reports it (e.g. `unknown-op`).
  Run `describe` first when unsure what a server supports.
