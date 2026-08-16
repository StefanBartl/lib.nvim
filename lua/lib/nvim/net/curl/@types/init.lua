---@meta
---@module 'lib.nvim.net.curl.@types'

---Basic auth credentials for `Lib.Net.Curl.FetchOpts.auth` (`-u user:pass`).
---@class Lib.Net.Curl.BasicAuth
---@field user string
---@field pass string

---Options for `require("lib.nvim.net.curl").fetch_json` / `fetch_json_blocking`.
---@class Lib.Net.Curl.FetchOpts
---@field method? string HTTP method (default `"GET"`)
---@field headers? table<string, string> Extra headers, one `-H` per entry
---@field bearer_token? string Sent as `Authorization: Bearer <token>`
---@field query? table<string, string> URL-encoded and appended as `?k=v&...`
---@field timeout_ms? integer Passed through to `vim.system`'s `timeout` / `wait(timeout)`
---@field body? string Raw request body, sent via `-d`
---@field auth? Lib.Net.Curl.BasicAuth Basic auth (`-u user:pass`)
---@field form? table<string, string> Multipart form fields, one `-F "k=v"` per entry; a value starting with `@` is curl's own file-upload syntax
---@field raw_args? string[] Extra curl arguments appended verbatim — an escape hatch for anything not otherwise covered
---@field http_version? "1.0"|"1.1"|"2" Forces `--http1.0`/`--http1.1`/`--http2`
---@field proxy? string Sent as `-x <proxy>`
---@field insecure? boolean Sent as `-k` (skip TLS certificate verification)

---A response as it actually came back — status, headers, body — undecoded.
---What `fetch_raw`/`fetch_raw_blocking` return on success, in place of
---`fetch_json`'s already-parsed JSON value.
---@class Lib.Net.Curl.RawResponse
---@field status integer HTTP status code, parsed from the response's own status line — curl's process exit code says nothing about this (it is 0 for a successful request regardless of the status returned).
---@field status_text string Reason phrase from the status line (`"OK"`, `"Not Found"`, ...); `""` if the server sent none.
---@field headers table<string, string> Response headers, keys lowercased so a lookup does not depend on a server's own casing convention.
---@field body string Raw response body text, exactly as received.

---@class Lib.Net.Curl
---@field fetch_json fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil, cb: fun(ok: boolean, data_or_err: any, raw_obj: vim.SystemCompleted))
---@field fetch_json_blocking fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil): boolean, any, vim.SystemCompleted
---@field fetch_raw fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil, cb: fun(ok: boolean, response_or_err: Lib.Net.Curl.RawResponse|string, raw_obj: vim.SystemCompleted))
---@field fetch_raw_blocking fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil): boolean, Lib.Net.Curl.RawResponse|string, vim.SystemCompleted
---@field download fun(url: string, dest_path: string, opts: Lib.Net.Curl.FetchOpts|nil, cb: fun(ok: boolean, response_or_err: Lib.Net.Curl.RawResponse|string, raw_obj: vim.SystemCompleted))
---@field download_blocking fun(url: string, dest_path: string, opts: Lib.Net.Curl.FetchOpts|nil): boolean, Lib.Net.Curl.RawResponse|string, vim.SystemCompleted
