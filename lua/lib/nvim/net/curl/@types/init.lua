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

---@class Lib.Net.Curl
---@field fetch_json fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil, cb: fun(ok: boolean, data_or_err: any, raw_obj: vim.SystemCompleted))
---@field fetch_json_blocking fun(url: string, opts: Lib.Net.Curl.FetchOpts|nil): boolean, any, vim.SystemCompleted
