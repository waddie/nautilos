(declare-project
  :name "nautilos"
  :description "Agent-facing nREPL tool: a daemon plus thin CLI that lets an agent drive any nREPL server and keep accrued REPL state across calls."
  :author "Tom Waddington"
  :license "MIT"
  :version "0.2.0"
  :dependencies ["https://github.com/waddie/nrepl-janet.git"])

(declare-executable
  :name "nautilos"
  :entry "src/main.janet"
  :install false)
