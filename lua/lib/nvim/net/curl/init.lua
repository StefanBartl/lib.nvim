---@module 'lib.nvim.net.curl'
--- Async (and blocking) HTTP-via-curl helper with JSON-body decoding.
---
--- Builds a `curl` argv from `opts` (method, headers, bearer token, query
--- string, body), spawns it through `vim.system` (requires Neovim 0.10+),
--- and decodes a JSON response for you. No `jobstart` fallback — this is a
--- new, opt-in module, so `vim.system` is a hard requirement.
---
--- Usage:
--- ```lua
--- local curl = require("lib.nvim.net.curl")
---
--- curl.fetch_json("https://api.example.com/items", {
---   method = "GET",
---   query = { limit = "10" },
---   bearer_token = "abc123",
--- }, function(ok, data, raw)
---   if ok then
---     vim.print(data)
---   else
---     vim.notify("fetch failed: " .. data, vim.log.levels.ERROR)
---   end
--- end)
---
--- local ok, data, raw = curl.fetch_json_blocking("https://api.example.com/items")
--- ```

require("lib.nvim.net.curl.@types")

local M = {}

---Percent-encode `s` for safe use in a URL query component.
---@param s string
---@return string
local function url_encode(s)
  return (s:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

---Build the `?k=v&...` query string (with leading `?`) for `query`, or `""`.
---@param query table<string, string>|nil
---@return string
local function build_query_string(query)
  if not query or next(query) == nil then
    return ""
  end
  local parts = {}
  for k, v in pairs(query) do
    parts[#parts + 1] = url_encode(tostring(k)) .. "=" .. url_encode(tostring(v))
  end
  return "?" .. table.concat(parts, "&")
end

---Build the curl argv table for `url`/`opts`.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts
---@return string[]
local function build_argv(url, opts)
  local argv = { "curl", "-sS", "-X", opts.method or "GET" }

  for key, value in pairs(opts.headers or {}) do
    argv[#argv + 1] = "-H"
    argv[#argv + 1] = key .. ": " .. value
  end

  if opts.bearer_token then
    argv[#argv + 1] = "-H"
    argv[#argv + 1] = "Authorization: Bearer " .. opts.bearer_token
  end

  if opts.body then
    argv[#argv + 1] = "-d"
    argv[#argv + 1] = opts.body
  end

  argv[#argv + 1] = url .. build_query_string(opts.query)

  return argv
end

---Decode a completed curl `obj` into the `(ok, data_or_err, raw_obj)` contract.
---@param obj vim.SystemCompleted
---@return boolean ok
---@return any data_or_err
local function decode_result(obj)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err
  end

  local ok, decoded = pcall(vim.json.decode, obj.stdout)
  if not ok then
    return false, "invalid JSON response"
  end
  return true, decoded
end

---Fetch `url` and decode the response body as JSON, asynchronously.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, data_or_err:any, raw_obj:vim.SystemCompleted)
function M.fetch_json(url, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts)

  vim.system(argv, { text = true, timeout = opts.timeout_ms }, function(obj)
    local ok, data_or_err = decode_result(obj)
    cb(ok, data_or_err, obj)
  end)
end

---Fetch `url` and decode the response body as JSON, blocking the caller.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return any data_or_err
---@return vim.SystemCompleted raw_obj
function M.fetch_json_blocking(url, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts)

  local obj = vim.system(argv, { text = true }):wait(opts.timeout_ms)
  local ok, data_or_err = decode_result(obj)
  return ok, data_or_err, obj
end

return M
