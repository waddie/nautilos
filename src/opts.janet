###
### opts.janet
###
### Translate string-keyed request tables (JSON from the CLI socket or MCP
### params) into the keyword option tables nrepl/client expects. Shared by the
### daemon and the MCP server so the two front-ends cannot drift.

(defn eval-opts
  "The `:file`/`:line`/`:column` eval options present in `req`."
  [req]
  (def o @{})
  (when-let [f (get req "file")] (put o :file f))
  (when-let [l (get req "line")] (put o :line l))
  (when-let [c (get req "column")] (put o :column c))
  o)

(defn load-opts
  "The `:file-name`/`:file-path` load-file options present in `req`."
  [req]
  (def o @{})
  (when-let [n (get req "file-name")] (put o :file-name n))
  (when-let [p (get req "file-path")] (put o :file-path p))
  o)
