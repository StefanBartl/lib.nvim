---@module 'lib.nvim.net.curl'
--- Async (and blocking) HTTP-via-curl helper, three tiers (JSON, raw,
--- download-to-file).
---
--- Builds a `curl` argv from `opts` (method, headers, bearer token, query
--- string, body, form fields, basic auth, proxy, HTTP version, raw
--- passthrough args), spawns it through `vim.system` (requires Neovim
--- 0.10+). No `jobstart` fallback — this is a new, opt-in module, so
--- `vim.system` is a hard requirement.
---
--- `fetch_json`/`fetch_json_blocking` decode the response body as JSON for a
--- caller that already knows the answer is JSON. `fetch_raw`/
--- `fetch_raw_blocking` return the response verbatim instead — status,
--- headers, body, undecoded — for a caller that needs to *show* the
--- response (a request-runner UI, say) or whose content type is not JSON at
--- all. Neither is a special case of the other: `fetch_json` never sees a
--- status code or headers at all (curl's own process exit code says
--- nothing about the HTTP status — it is `0` for a successful *request*
--- regardless of whether the server answered `200` or `404`), and
--- `fetch_raw` never assumes the body parses as anything in particular.
--- `download`/`download_blocking` are a third tier: the body is written
--- straight to a file (`-o`) instead of buffered in memory, for responses
--- too large — or simply not needed — to hold as a Lua string.
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
---
--- local ok2, resp = curl.fetch_raw_blocking("https://api.example.com/items")
--- if ok2 then
---   print(resp.status, resp.status_text, resp.headers["content-type"])
---   print(resp.body)
--- end
---
--- local ok3, resp3 = curl.download_blocking("https://example.com/big.zip", "/tmp/big.zip")
--- if ok3 then
---   print(resp3.status) -- resp3.body is "" -- the body went to /tmp/big.zip
--- end
--- ```

require("lib.nvim.net.curl.@types")

local nvim_json = require("lib.nvim.json")

local M = {}

---@internal
---Percent-encode `s` for safe use in a URL query component.
---@param s string
---@return string
local function url_encode(s)
  return (
    s:gsub("([^%w%-%.%_%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  )
end

---@internal
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

---@internal
---Build the curl argv table for `url`/`opts`.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts
---@param include_headers boolean? Add `-i`, so the response headers precede
---the body in stdout — what `fetch_raw`/`fetch_raw_blocking` need to parse
---status and headers out; `fetch_json`/`fetch_json_blocking` leave this
---unset, since a header block would break their JSON decode.
---@param download_dest string? Set by `download`/`download_blocking`: the
---body goes to this file (`-o`) instead of stdout, headers are dumped to
---stdout separately (`-D -`) since `-i` and `-o` don't compose the way
---`fetch_raw` needs (with `-o`, `-i` would write headers into the file
---too). Mutually exclusive with `include_headers`.
---@return string[]
local function build_argv(url, opts, include_headers, download_dest)
  local argv = { "curl", "-sS", "-X", opts.method or "GET" }
  if include_headers then
    argv[#argv + 1] = "-i"
  elseif download_dest then
    argv[#argv + 1] = "-D"
    argv[#argv + 1] = "-"
    argv[#argv + 1] = "-o"
    argv[#argv + 1] = download_dest
  end

  if opts.insecure then
    argv[#argv + 1] = "-k"
  end

  if opts.http_version == "1.0" then
    argv[#argv + 1] = "--http1.0"
  elseif opts.http_version == "1.1" then
    argv[#argv + 1] = "--http1.1"
  elseif opts.http_version == "2" then
    argv[#argv + 1] = "--http2"
  end

  if opts.proxy then
    argv[#argv + 1] = "-x"
    argv[#argv + 1] = opts.proxy
  end

  if opts.auth then
    argv[#argv + 1] = "-u"
    argv[#argv + 1] = (opts.auth.user or "") .. ":" .. (opts.auth.pass or "")
  end

  for key, value in pairs(opts.headers or {}) do
    argv[#argv + 1] = "-H"
    argv[#argv + 1] = key .. ": " .. value
  end

  if opts.bearer_token then
    argv[#argv + 1] = "-H"
    argv[#argv + 1] = "Authorization: Bearer " .. opts.bearer_token
  end

  -- A value starting with "@" is curl's own file-upload syntax (-F
  -- "field=@/path/to/file") and works unchanged — no separate file-upload
  -- option needed.
  for key, value in pairs(opts.form or {}) do
    argv[#argv + 1] = "-F"
    argv[#argv + 1] = key .. "=" .. value
  end

  if opts.body then
    argv[#argv + 1] = "-d"
    argv[#argv + 1] = opts.body
  end

  for _, raw in ipairs(opts.raw_args or {}) do
    argv[#argv + 1] = raw
  end

  argv[#argv + 1] = url .. build_query_string(opts.query)

  return argv
end

---@internal
---Decode a completed curl `obj` into the `(ok, data_or_err, raw_obj)` contract.
---@param obj vim.SystemCompleted
---@return boolean ok
---@return any data_or_err
local function decode_result(obj)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err
  end

  local decoded, err = nvim_json.decode(obj.stdout)
  if err then
    return false, "invalid JSON response"
  end
  return true, decoded
end

---@internal
---Parse curl `-i` output (response headers, then a blank line, then the
---body) into status/headers/body. curl's own process exit code says nothing
---about the HTTP status — it is 0 for a successful *request* regardless of
---whether the server answered 200 or 404 — so this is the only way to learn
---what actually came back.
---
---Loops past any informational response (a `100 Continue` preamble, or a
---redirect hop if the caller ever passes `-L`, which `build_argv` does not
---today): each 1xx/redirect response is itself a complete
---"status line + headers + blank line" block, immediately followed by
---another one, so the loop keeps unwrapping blocks until it finds one not
---followed by a further `HTTP/` line — that one is the real, final response.
---@param output string Raw stdout from a curl invocation built with `include_headers = true`.
---@return Lib.Net.Curl.RawResponse? response `nil` on unparseable output.
---@return string? err Set only when `response` is `nil`.
local function parse_raw_response(output)
  while true do
    if not output:match("^HTTP/") then
      return nil, "no HTTP status line in curl output"
    end
    local sep_s, sep_e = output:find("\r?\n\r?\n")
    local block, rest
    if sep_s then
      block, rest = output:sub(1, sep_s - 1), output:sub(sep_e + 1)
    else
      -- Headers with no blank-line terminator at all (a truncated or
      -- header-only response) — treat everything as headers, body empty,
      -- rather than guessing where one might have started.
      block, rest = output, ""
    end

    local lines = vim.split(block, "\r?\n")
    local code, text = lines[1]:match("^HTTP/[%d%.]+%s+(%d+)%s*(.-)%s*$")
    if not code then
      return nil, "malformed status line: " .. lines[1]
    end

    if rest:match("^HTTP/") then
      -- An intermediate block (1xx, or a redirect hop) — unwrap and keep
      -- going; this one is not the caller's answer.
      output = rest
    else
      local headers = {}
      for i = 2, #lines do
        local k, v = lines[i]:match("^([^:]+):%s*(.-)%s*$")
        if k then
          headers[k:lower()] = v
        end
      end
      return { status = tonumber(code), status_text = text or "", headers = headers, body = rest }
    end
  end
end

---Fetch `url` and return the response verbatim — status, headers and body,
---undecoded — asynchronously. The second, "Postman-lite" tier alongside
---`fetch_json`: that one is right when the caller already knows the answer
---is JSON and only wants the decoded value; this one is for a caller that
---needs to *show* the response, or one whose content type is not JSON at
---all.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, response_or_err:Lib.Net.Curl.RawResponse|string, raw_obj:vim.SystemCompleted)
function M.fetch_raw(url, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts, true)

  vim.system(argv, { text = true, timeout = opts.timeout_ms }, function(obj)
    if obj.code ~= 0 then
      local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
      cb(false, err, obj)
      return
    end
    local response, err = parse_raw_response(obj.stdout)
    if not response then
      cb(false, err, obj)
      return
    end
    cb(true, response, obj)
  end)
end

---Fetch `url` and return the response verbatim, blocking the caller. See
---`fetch_raw` for what "verbatim" means and when to reach for it instead of
---`fetch_json_blocking`.
---@param url string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return Lib.Net.Curl.RawResponse|string response_or_err
---@return vim.SystemCompleted raw_obj
function M.fetch_raw_blocking(url, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts, true)

  local obj = vim.system(argv, { text = true }):wait(opts.timeout_ms)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err, obj
  end
  local response, err = parse_raw_response(obj.stdout)
  if not response then
    return false, err, obj
  end
  return true, response, obj
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

---Fetch `url` and write the response body directly to `dest_path` instead
---of buffering it in memory, asynchronously. Returns status/headers like
---`fetch_raw` — `response.body` is always `""` here, since the body went
---to `dest_path`, not stdout.
---@param url string
---@param dest_path string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@param cb fun(ok:boolean, response_or_err:Lib.Net.Curl.RawResponse|string, raw_obj:vim.SystemCompleted)
function M.download(url, dest_path, opts, cb)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts, false, dest_path)

  vim.system(argv, { text = true, timeout = opts.timeout_ms }, function(obj)
    if obj.code ~= 0 then
      local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
      cb(false, err, obj)
      return
    end
    local response, err = parse_raw_response(obj.stdout)
    if not response then
      cb(false, err, obj)
      return
    end
    cb(true, response, obj)
  end)
end

---Blocking counterpart to `M.download`.
---@param url string
---@param dest_path string
---@param opts Lib.Net.Curl.FetchOpts|nil
---@return boolean ok
---@return Lib.Net.Curl.RawResponse|string response_or_err
---@return vim.SystemCompleted raw_obj
function M.download_blocking(url, dest_path, opts)
  if not vim.system then
    error("lib.nvim.net.curl requires Neovim 0.10+ (vim.system)")
  end
  opts = opts or {}

  local argv = build_argv(url, opts, false, dest_path)

  local obj = vim.system(argv, { text = true }):wait(opts.timeout_ms)
  if obj.code ~= 0 then
    local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or ("curl exited " .. obj.code)
    return false, err, obj
  end
  local response, err = parse_raw_response(obj.stdout)
  if not response then
    return false, err, obj
  end
  return true, response, obj
end

return M
