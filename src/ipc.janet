###
### ipc.janet
###
### Newline-delimited JSON framing for the daemon <-> CLI unix socket. One
### request and one response per connection. spork/json encodes compactly with
### no literal newlines inside strings, so a single `\n` cleanly delimits a
### message.

(import spork/json :as json)

(defn read-msg
  "Read one newline-delimited JSON object from `stream`. Returns the decoded
  table, or nil on EOF before any complete message."
  [stream]
  (def buf @"")
  (var nl nil)
  (forever
    (set nl (string/find "\n" buf))
    (if nl (break))
    (def chunk (try (net/read stream 4096) ([_] nil)))
    (if (nil? chunk) (break))
    (buffer/push-string buf chunk))
  (cond
    nl (json/decode (string/slice buf 0 nl))
    (empty? buf) nil
    (json/decode (string buf))))

(defn write-msg
  "Encode `data` as JSON and write it newline-delimited to `stream`."
  [stream data]
  (net/write stream (buffer (json/encode data) "\n")))
