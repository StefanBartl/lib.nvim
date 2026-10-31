---@module 'lib.nvim.net.github'
--- GitHub REST API requests on top of `lib.nvim.net.curl`, plus token
--- resolution.
---
--- `request`/`request_blocking` add what every GitHub caller otherwise
--- repeats: the `Accept: application/vnd.github+json` and
--- `X-GitHub-Api-Version` headers, the bearer token (through curl's `-K -`
--- config path, never argv), `If-None-Match` for a conditional request, and
--- one error contract for everything GitHub can answer that is not a usable
--- result -- a 4xx/5xx status, a `200` whose body is a `{"message": ...}`
--- error object, an exhausted rate limit (the error says when it resets).
--- A `304 Not Modified` is not an error: the result says `not_modified`.
---
--- `token` resolves a token: a caller-named environment variable first, then
--- `gh auth token`. It never reads `GITHUB_TOKEN` unless the caller names
--- that variable itself, and it strips `GITHUB_TOKEN` from the `gh` child's
--- environment too (gh would otherwise print it back). No error message
--- ever carries the token.
---
--- Usage:
--- ```lua
--- local github = require("lib.nvim.net.github")
---
--- local token = github.token({ env_var = "MY_PLUGIN_GITHUB_TOKEN" })
--- local res, err = github.request_blocking("/repos/owner/repo/actions/runs", {
---   token = token,
---   query = { head_sha = sha, per_page = "20" },
--- })
--- if res and not res.not_modified then
---   vim.print(res.data.workflow_runs, res.etag, res.rate_limit.remaining)
--- end
--- ```

require("lib.nvim.net.github.@types")

local curl = require("lib.nvim.net.curl")
local nvim_json = require("lib.nvim.json")
local strings = require("lib.lua.strings.core")

local M = {}

M.API_BASE = "https://api.github.com"
M.API_VERSION = "2022-11-28"

--- The fetch tiers of `lib.nvim.net.curl` have no limits of their own; a
--- GitHub answer is small JSON, so an unbounded one is a broken endpoint.
--- `false` in `opts` lifts either default.
local DEFAULT_TIMEOUT_MS = 15000
local DEFAULT_MAX_BYTES = 5 * 1024 * 1024
local DEFAULT_GH_TIMEOUT_MS = 5000

--- The keys a GitHub error object carries. A `200` body made only of these
--- is an error; a real resource that happens to have a `message` field (a
--- commit, a tag) has other keys too and passes.
local ERROR_KEYS = { message = true, documentation_url = true, status = true, errors = true }

---@internal
---@param path_or_url string
---@param base string|nil
---@return string
local function resolve_url(path_or_url, base)
  if path_or_url:match("^https?://") then
    return path_or_url
  end
  local prefix = (base or M.API_BASE):gsub("/+$", "")
  if path_or_url:sub(1, 1) ~= "/" then
    path_or_url = "/" .. path_or_url
  end
  return prefix .. path_or_url
end

---@internal
---`false` lifts a default, `nil` keeps it.
---@param value integer|false|nil
---@param default integer
---@return integer|nil
local function limit(value, default)
  if value == false then
    return nil
  end
  return value or default
end

---@internal
---@param opts Lib.Net.Github.RequestOpts
---@return Lib.Net.Curl.FetchOpts
local function curl_opts(opts)
  local headers = {
    Accept = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = M.API_VERSION,
  }
  if opts.etag then
    headers["If-None-Match"] = opts.etag
  end
  return {
    method = opts.method,
    headers = headers,
    bearer_token = opts.token,
    query = opts.query,
    timeout_ms = limit(opts.timeout_ms, DEFAULT_TIMEOUT_MS),
    max_bytes = limit(opts.max_bytes, DEFAULT_MAX_BYTES),
  }
end

---@internal
---@param value string|nil
---@return integer|nil
local function header_int(value)
  local n = tonumber(value)
  return n and math.floor(n) or nil
end

---@internal
---@param reset integer|nil
---@return string
local function describe_reset(reset)
  if not reset then
    return "reset time unknown"
  end
  local wait = math.max(0, reset - os.time())
  return ("resets at %s (in %ds)"):format(os.date("!%Y-%m-%dT%H:%M:%SZ", reset), wait)
end

---@internal
---@param data any
---@return string|nil message
local function error_message(data)
  if type(data) ~= "table" or type(data.message) ~= "string" then
    return nil
  end
  for key in pairs(data) do
    if not ERROR_KEYS[key] then
      return nil
    end
  end
  return data.message
end

---@internal
---Turn a raw curl response into this module's `(result, err)` contract.
---@param resp Lib.Net.Curl.RawResponse
---@return Lib.Net.Github.Response|nil
---@return string|nil err
local function interpret(resp)
  local headers = resp.headers or {}
  local rate_limit = {
    remaining = header_int(headers["x-ratelimit-remaining"]),
    reset = header_int(headers["x-ratelimit-reset"]),
  }

  if (resp.status == 403 or resp.status == 429) and rate_limit.remaining == 0 then
    return nil,
      ("GitHub API rate limit exhausted (HTTP %d); %s"):format(
        resp.status,
        describe_reset(rate_limit.reset)
      )
  end

  local result = {
    status = resp.status,
    etag = headers["etag"],
    headers = headers,
    not_modified = resp.status == 304,
    rate_limit = rate_limit,
  }
  if result.not_modified then
    return result
  end

  local data, decode_err
  if resp.body and resp.body:match("%S") then
    data, decode_err = nvim_json.decode(resp.body)
  end

  if resp.status >= 400 then
    local message = type(data) == "table" and type(data.message) == "string" and data.message
      or resp.status_text
    if message and message ~= "" then
      return nil, ("GitHub API error: HTTP %d: %s"):format(resp.status, message)
    end
    return nil, ("GitHub API error: HTTP %d"):format(resp.status)
  end

  if decode_err then
    return nil, ("GitHub API error: HTTP %d: invalid JSON response"):format(resp.status)
  end

  local message = error_message(data)
  if message then
    return nil, ("GitHub API error: HTTP %d: %s"):format(resp.status, message)
  end

  result.data = data
  return result
end

---@internal
---@param ok boolean
---@param resp_or_err Lib.Net.Curl.RawResponse|string
---@return Lib.Net.Github.Response|nil
---@return string|nil err
local function finish(ok, resp_or_err)
  if not ok then
    return nil, "GitHub request failed: " .. strings.trim(tostring(resp_or_err))
  end
  return interpret(resp_or_err --[[@as Lib.Net.Curl.RawResponse]])
end

---Send a GitHub REST API request, asynchronously. `cb` runs on the main
---loop, never synchronously from inside this call.
---@param path_or_url string An API path (`/repos/o/r/...`) or an absolute URL (a `Link` header's next page).
---@param opts Lib.Net.Github.RequestOpts|nil
---@param cb fun(result: Lib.Net.Github.Response|nil, err: string|nil)
function M.request(path_or_url, opts, cb)
  opts = opts or {}
  local url = resolve_url(path_or_url, opts.api_base)
  local copts = curl_opts(opts)
  local function done(ok, resp_or_err)
    local result, err = finish(ok, resp_or_err)
    vim.schedule(function()
      cb(result, err)
    end)
  end
  if opts.transport then
    opts.transport(url, copts, done)
  else
    curl.fetch_raw(url, copts, function(ok, resp_or_err)
      done(ok, resp_or_err)
    end)
  end
end

---Send a GitHub REST API request, blocking the caller. Same result and
---error contract as `request`.
---@param path_or_url string
---@param opts Lib.Net.Github.RequestOpts|nil
---@return Lib.Net.Github.Response|nil result
---@return string|nil err
function M.request_blocking(path_or_url, opts)
  opts = opts or {}
  local url = resolve_url(path_or_url, opts.api_base)
  local copts = curl_opts(opts)
  if not opts.transport then
    local ok, resp_or_err = curl.fetch_raw_blocking(url, copts)
    return finish(ok, resp_or_err)
  end

  -- An injected transport has the async shape; a fake one usually answers
  -- synchronously, anything else is waited for up to the request's timeout.
  local settled, ok, resp_or_err = false, false, nil
  opts.transport(url, copts, function(o, r)
    settled, ok, resp_or_err = true, o, r
  end)
  if not settled then
    vim.wait(copts.timeout_ms or DEFAULT_TIMEOUT_MS, function()
      return settled
    end, 10)
  end
  if not settled then
    return nil, "GitHub request failed: transport did not answer"
  end
  return finish(ok, resp_or_err --[[@as Lib.Net.Curl.RawResponse|string]])
end

---@internal
---The current environment without `GITHUB_TOKEN`: gh prints that variable
---back as its token when it is set, which would defeat the rule that a
---broad Actions token is only ever used when a caller names it.
---@return table<string, string>
local function gh_env()
  local env = vim.fn.environ()
  env.GITHUB_TOKEN = nil
  return env
end

---@internal
---@param argv string[]
---@param sys_opts Lib.Net.Github.RunnerOpts
---@return Lib.Net.Github.RunnerResult
local function default_runner(argv, sys_opts)
  local ok, proc = pcall(vim.system, argv, {
    text = true,
    env = sys_opts.env,
    clear_env = true,
  })
  if not ok then
    return { code = -1, stdout = "", stderr = tostring(proc) }
  end
  local obj = proc:wait(sys_opts.timeout_ms)
  return { code = obj.code, stdout = obj.stdout or "", stderr = obj.stderr or "" }
end

---Resolve a GitHub token: `opts.env_var` when that variable is set and
---non-empty, else `gh auth token`. `GITHUB_TOKEN` is read only when the
---caller passes that name as `env_var`.
---@param opts Lib.Net.Github.TokenOpts|nil
---@return string|nil token
---@return string source_or_reason `"env:<NAME>"` or `"gh"` on success, otherwise why no token was found.
function M.token(opts)
  opts = opts or {}
  local reasons = {}

  if opts.env_var and opts.env_var ~= "" then
    -- vim.env, not os.getenv: on Windows the CRT's copy misses a variable
    -- set after startup through vim.env/setenv.
    local value = vim.env[opts.env_var]
    value = value and strings.trim(value)
    if value and value ~= "" then
      return value, "env:" .. opts.env_var
    end
    reasons[#reasons + 1] = ("$%s is not set"):format(opts.env_var)
  end

  local run = opts.runner or default_runner
  local res = run({ "gh", "auth", "token" }, {
    env = gh_env(),
    timeout_ms = opts.timeout_ms or DEFAULT_GH_TIMEOUT_MS,
  })
  local out = strings.trim(res.stdout or "")
  if res.code == 0 and out ~= "" then
    return out, "gh"
  end
  if res.code == 0 then
    reasons[#reasons + 1] = "`gh auth token` printed no token"
  else
    -- stderr only, never stdout: on a partial failure stdout may be a token.
    local first = strings.trim((res.stderr or ""):match("[^\r\n]*") or "")
    reasons[#reasons + 1] = ("`gh auth token` failed (exit %s)%s"):format(
      tostring(res.code),
      first ~= "" and (": " .. first) or ""
    )
  end
  return nil, table.concat(reasons, "; ")
end

return M
