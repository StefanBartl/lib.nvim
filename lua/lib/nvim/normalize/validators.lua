---@module 'lib.nvim.normalize.validators'

local norm_utils = require("lib.lua.lazy").require("lib.nvim.normalize.utils")

local M = {}

--- Convert value into a boolean (loose parsing).
--- Accepts booleans; numbers 0/1; strings "true/false/yes/no/on/off/1/0" (case-insensitive).
---@param v any
---@return boolean|nil
function M.to_bool(v)
  local t = type(v)
  if t == "boolean" then
    return v
  end
  if t == "number" then
    if v == 0 then
      return false
    end
    if v == 1 then
      return true
    end
    return nil
  end
  if t == "string" then
    local s = v:lower()
    if s == "true" or s == "yes" or s == "on" or s == "1" then
      return true
    end
    if s == "false" or s == "no" or s == "off" or s == "0" then
      return false
    end
  end
  return nil
end

--- Convert value to integer; optionally clamp.
---@param v any
---@param min integer|nil
---@param max integer|nil
---@return integer|nil
function M.to_int(v, min, max)
  local n = tonumber(v)
  if not n then
    return nil
  end
  n = math.floor(n + 0) -- truncate toward zero
  ---@cast n integer
  if min or max then
    n = norm_utils.clamp(n, min, max)
  end
  return n
end

--- Convert value to float; optionally clamp and round to a given precision.
---@param v any
---@param min number|nil
---@param max number|nil
---@param precision integer|nil  -- number of fractional digits to keep (>=0)
---@return number|nil
function M.to_float(v, min, max, precision)
  local n = tonumber(v)
  if not n then
    return nil
  end
  if min or max then
    n = norm_utils.clamp(n, min, max)
  end
  if precision and precision >= 0 then
    local k = 10 ^ precision
    n = math.floor(n * k + 0.5) / k
  end
  return n
end

--- Return string if non-empty; optionally trim.
---@param v any
---@param allow_empty boolean|nil
---@param do_trim boolean|nil
---@return string|nil
function M.to_string(v, allow_empty, do_trim)
  if type(v) ~= "string" then
    return nil
  end
  local s = do_trim and norm_utils.trim(v) or v
  if not allow_empty and s == "" then
    return nil
  end
  return s
end

--- Map a value to an enum entry (case-insensitive by default).
---@param v any
---@param allowed Lib.Normalize.StringList
---@param case_insensitive boolean|nil
---@return string|nil
function M.to_enum(v, allowed, case_insensitive)
  if type(v) ~= "string" then
    return nil
  end
  local s = v
  if case_insensitive ~= false then
    s = s:lower()
  end
  for i = 1, #allowed do
    local a = allowed[i]
    if case_insensitive ~= false then
      if type(a) == "string" and a:lower() == s then
        return a
      end
    else
      if a == s then
        return a
      end
    end
  end
  return nil
end

--- Convert value into a list of strings.
--- Accepts:
---   * string with separators (comma/space by default) → split
---   * list of strings → filtered to strings, option to dedup and trim
---@param v any
---@param opts {sep?:string, trim?:boolean, dedup?:boolean}|nil
---@return Lib.Normalize.StringList|nil
function M.to_string_list(v, opts)
  opts = opts or {}
  local sep = opts.sep or "[%s,]+"
  local out = {} ---@type Lib.Normalize.StringList
  if type(v) == "string" then
    for token in v:gmatch("[^" .. sep .. "]+") do
      local s = opts.trim and norm_utils.trim(token) or token
      if s ~= "" then
        out[#out + 1] = s
      end
    end
  elseif type(v) == "table" then
    for i = 1, #v do
      if type(v[i]) == "string" then
        local s = opts.trim and norm_utils.trim(v[i]) or v[i]
        if s ~= "" then
          out[#out + 1] = s
        end
      end
    end
  else
    return nil
  end
  if opts.dedup then
    out = norm_utils.dedup_strings(out)
  end
  return out
end

--- Convert a shell-like command (string or argv) into argv (best-effort).
--- Supports simple double-quoted segments; does not resolve escapes comprehensively.
---@param v any
---@return Lib.Normalize.StringList|nil
function M.to_argv(v)
  if type(v) == "table" then
    local out = {} ---@type Lib.Normalize.StringList
    for i = 1, #v do
      if type(v[i]) == "string" and v[i] ~= "" then
        out[#out + 1] = v[i]
      else
        return nil
      end
    end
    return #out > 0 and out or nil
  elseif type(v) == "string" then
    local s = norm_utils.trim(v)
    if s == "" then
      return nil
    end
    local out = {} ---@type Lib.Normalize.StringList
    local i, len = 1, #s
    while i <= len do
      while i <= len and s:sub(i, i):match("%s") do
        i = i + 1
      end
      if i > len then
        break
      end
      local ch = s:sub(i, i)
      if ch == '"' then
        local j = i + 1
        while j <= len and s:sub(j, j) ~= '"' do
          j = j + 1
        end
        out[#out + 1] = s:sub(i + 1, j - 1)
        i = j + 1
      else
        local j = i
        while j <= len and not s:sub(j, j):match("%s") do
          j = j + 1
        end
        out[#out + 1] = s:sub(i, j - 1)
        i = j
      end
    end
    return #out > 0 and out or nil
  end
  return nil
end

--- Map a user severity to vim.diagnostic.severity or nil.
--- Accepts "error|warn|warning|info|hint|all|''" and numeric pass-through.
---@param v any
---@return integer|nil
function M.to_diagnostic_severity(v)
  if type(v) == "number" then
    return v
  end
  if type(v) ~= "string" then
    return nil
  end
  local s = v:lower()
  if s == "" or s == "all" then
    return nil
  end
  if s == "error" or s == "err" then
    return vim.diagnostic.severity.ERROR
  end
  if s == "warn" or s == "warning" then
    return vim.diagnostic.severity.WARN
  end
  if s == "info" then
    return vim.diagnostic.severity.INFO
  end
  if s == "hint" then
    return vim.diagnostic.severity.HINT
  end
  return nil
end

--- Map a user level to vim.log.levels.* or nil.
--- Accepts "trace|debug|info|warn|error|off" and numeric pass-through.
---@param v any
---@return integer|nil
function M.to_log_level(v)
  if type(v) == "number" then
    return v
  end
  if type(v) ~= "string" then
    return nil
  end
  local s = v:lower()
  if s == "trace" then
    return vim.log.levels.TRACE
  end
  if s == "debug" then
    return vim.log.levels.DEBUG
  end
  if s == "info" then
    return vim.log.levels.INFO
  end
  if s == "warn" then
    return vim.log.levels.WARN
  end
  if s == "error" then
    return vim.log.levels.ERROR
  end
  if s == "off" then
    return nil
  end
  return nil
end

--- Normalize a filesystem path and optionally ensure existence/type.
--- type_filter: "file"|"directory"|nil
---@param v any
---@param type_filter string|nil
---@param must_exist boolean|nil
---@return string|nil
function M.to_path(v, type_filter, must_exist)
  local s = M.to_string(v, false, true)
  if not s then
    return nil
  end
  s = norm_utils.normalize_path(s)
  if must_exist then
    local kind = norm_utils.path_kind(s)
    if kind == "" then
      return nil
    end
    if type_filter and kind ~= type_filter then
      return nil
    end
  end
  return s
end



--- Validate that a value is an integer meeting a minimum bound, with optional nil allowance.
--- Contract:
---   * If v == nil and allow_nil == true  → ok=true, val=nil,  err=nil (caller can keep default)
---   * If v == nil and allow_nil == false → ok=false, val=nil,  err="<name> is required"
---   * If v is a number but not an integer (e.g. 1.5) → ok=false, err="<name> must be an integer"
---   * If v < min → ok=false, err="<name> must be ≥ <min>"
---   * Otherwise → ok=true, val=<integer>, err=nil
--- Rationale:
---   * This style produces a single, user-friendly error message without throwing.
---   * Returning the parsed integer (or nil) avoids re-parsing at call sites.
--- Example:
---   local ok, n, err = M.as_int("inner_pad", user.inner_pad, 0, false)
---   if not ok then return false, nil, err end
---@param name string            -- logical option name for readable error messages
---@param v any                  -- user-provided value to check
---@param min integer            -- inclusive minimum bound the integer must satisfy
---@param allow_nil boolean      -- whether nil is acceptable (useful for optional fields)
---@return boolean ok            -- true if valid or allowed-nil; false on validation failure
---@return integer|nil val       -- normalized integer (or nil if allowed-nil case)
---@return string|nil err        -- non-empty error message on failure; nil on success
function M.as_int(name, v, min, allow_nil)
  if v == nil then
    if allow_nil then
      return true, nil, nil
    end
    return false, nil, name .. " is required"
  end
  if type(v) ~= "number" or v ~= math.floor(v) then
    return false, nil, name .. " must be an integer"
  end
  if v < min then
    return false, nil, string.format("%s must be ≥ %d", name, min)
  end
  ---@cast v integer
  return true, v, nil
end

--- Validate that a value is strictly boolean (true/false).
--- Contract:
---   * Only Lua booleans are accepted. Strings like "true"/"false" are NOT coerced here.
---   * On success → ok=true, val=<boolean>, err=nil
---   * On failure → ok=false, val=nil, err="<name> must be a boolean"
--- Rationale:
---   * Use strict validation at config boundaries to avoid surprising coercions.
---   * For permissive conversion, prefer `to_bool()` + `apply_bool_loose()`.
--- Example:
---   local ok, b, err = M.as_bool("auto_width", user.auto_width)
---   if not ok then return false, nil, err end
---@param name string            -- logical option name for readable error messages
---@param v any                  -- user-provided value to check
---@return boolean ok            -- true if v is a boolean
---@return boolean|nil val       -- boolean value on success; nil on failure
---@return string|nil err        -- non-empty error message on failure; nil on success
function M.as_bool(name, v)
  if type(v) ~= "boolean" then
    return false, nil, name .. " must be a boolean"
  end
  return true, v, nil
end

--- Check whether `v` equals one of `candidates` (plain `==` comparison, no
--- coercion). Useful for guarding enum-like config fields.
---@param v any
---@param candidates any[]
---@return boolean
function M.is_one_of(v, candidates)
  for i = 1, #candidates do
    if v == candidates[i] then
      return true
    end
  end
  return false
end

--- True when `bufnr` is a valid, currently-loaded buffer handle.
---@param bufnr any
---@return boolean
function M.buf_valid(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

--- True when `winid` is a valid window handle.
---@param winid any
---@return boolean
function M.win_valid(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@type Lib.Normalize.Validators
return M
