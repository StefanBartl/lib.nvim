---@meta
---@module 'lib.nvim.net.curl.@types'

---Options for `require("lib.nvim.net.curl").fetch_json` / `fetch_json_blocking`.
---@class Lib.Net.Curl.FetchOpts
---@field method? string HTTP method (default `"GET"`)
---@field headers? table<string, string> Extra headers, one `-H` per entry
---@field bearer_token? string Sent as `Authorization: Bearer <token>`
---@field query? table<string, string> URL-encoded and appended as `?k=v&...`
---@field timeout_ms? integer Passed through to `vim.system`'s `timeout` / `wait(timeout)`
---@field body? string Raw request body, sent via `-d`

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
