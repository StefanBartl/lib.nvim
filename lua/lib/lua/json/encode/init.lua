---@module 'lib.lua.json.encode'
--- Pure-Lua JSON encoder — the counterpart to `lib.lua.json.decode`.
---
--- Editor-independent by design (no `vim` API), so it works in plain Lua,
--- LuaJIT and Neovim alike. Where `vim.json.encode` is available it is NOT
--- used on purpose: this module guarantees identical behavior on every
--- platform and runtime.
---
---   local encode = require("lib.lua.json.encode")
---   encode({ a = 1, list = { 1, 2, 3 } })   -- '{"a":1,"list":[1,2,3]}'
---   encode.pretty({ a = 1 })                -- multi-line, 2-space indent
---
--- Semantics:
---   * strings        -> escaped per RFC 8259 (control chars as \u00XX)
---   * numbers        -> integers without trailing ".0"; NaN/Inf are an error
---   * booleans, nil  -> true/false/null (nil only representable as a value
---                       inside nothing — top-level nil encodes to "null")
---   * tables         -> contiguous 1..n integer keys => JSON array,
---                       otherwise JSON object; keys are stringified
---                       (string/number keys only) and sorted by default for
---                       deterministic output. Empty tables encode as "[]"
---                       (mirrors decode.is_array_like, which treats {} as
---                       array-like).
---   * cycles, functions, userdata, threads -> nil + error message
---
--- Errors are reported as `nil, err` — the encoder never throws.

local M = {}

-- =========================================================
-- String escaping
-- =========================================================

local NAMED_ESCAPES = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

---@param c string # single char
---@return string
local function escape_char(c)
  return NAMED_ESCAPES[c] or string.format("\\u%04x", c:byte())
end

---@param s string
---@return string
local function encode_string(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

-- =========================================================
-- Number formatting
-- =========================================================

---@param n number
---@return string|nil encoded
---@return string|nil err
local function encode_number(n)
  if n ~= n then
    return nil, "cannot encode NaN"
  end
  if n == math.huge or n == -math.huge then
    return nil, "cannot encode Infinity"
  end
  -- Integral values without a fractional marker ("1", not "1.0").
  -- math.type exists on Lua 5.3+; the modulo check covers 5.1/LuaJIT.
  ---@diagnostic disable-next-line: deprecated
  if (math.type and math.type(n) == "integer") or (n % 1 == 0 and math.abs(n) < 2 ^ 53) then
    return string.format("%.0f", n), nil
  end
  return string.format("%.14g", n), nil
end

-- =========================================================
-- Table shape helpers
-- =========================================================

--- Contiguous positive integer keys starting at 1 (Lua array semantics).
--- Same definition as `lib.lua.json.decode.to_string_array.is_array_like`,
--- duplicated locally to keep the encoder dependency-free.
---@param t table
---@return boolean
local function is_array_like(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then
      return false
    end
  end
  return true
end

-- =========================================================
-- Core encoder
-- =========================================================

---@param value any
---@param opts Lib.JSON.EncodeOpts
---@param indent string|nil # resolved indent unit, nil = compact
---@param level integer
---@param seen table # identity set for cycle detection
---@return string|nil encoded
---@return string|nil err
local function encode_value(value, opts, indent, level, seen)
  local t = type(value)

  if t == "nil" then
    return "null", nil
  elseif t == "boolean" then
    return value and "true" or "false", nil
  elseif t == "number" then
    return encode_number(value)
  elseif t == "string" then
    return encode_string(value), nil
  elseif t ~= "table" then
    return nil, "cannot encode value of type '" .. t .. "'"
  end

  if seen[value] then
    return nil, "cannot encode cyclic table"
  end
  seen[value] = true

  local open_pad, item_pad, close_pad = "", "", ""
  if indent then
    open_pad = "\n" .. indent:rep(level + 1)
    item_pad = open_pad
    close_pad = "\n" .. indent:rep(level)
  end

  local out
  if is_array_like(value) then
    local parts = {}
    for i = 1, #value do
      local enc, err = encode_value(value[i], opts, indent, level + 1, seen)
      if not enc then
        return nil, err
      end
      parts[i] = enc
    end
    if #parts == 0 then
      out = "[]"
    else
      out = "[" .. open_pad .. table.concat(parts, "," .. item_pad) .. close_pad .. "]"
    end
  else
    -- Object: string/number keys only; sorted for deterministic output
    -- (mirrors the stable key ordering of decode.table_to_string_array).
    local keys = {}
    for k in pairs(value) do
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" then
        return nil, "cannot encode table key of type '" .. kt .. "'"
      end
      keys[#keys + 1] = k
    end
    if opts.sort_keys ~= false then
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
    end

    local colon = indent and ": " or ":"
    local parts = {}
    for i, k in ipairs(keys) do
      local enc, err = encode_value(value[k], opts, indent, level + 1, seen)
      if not enc then
        return nil, err
      end
      parts[i] = encode_string(tostring(k)) .. colon .. enc
    end
    out = "{" .. open_pad .. table.concat(parts, "," .. item_pad) .. close_pad .. "}"
  end

  seen[value] = nil
  return out, nil
end

-- =========================================================
-- Public API
-- =========================================================

--- Encode a Lua value as a JSON string.
---@param value any
---@param opts? Lib.JSON.EncodeOpts
---@return string|nil encoded # JSON string, or nil on failure
---@return string|nil err     # error message when encoding failed
function M.encode(value, opts)
  opts = opts or {}

  local indent = opts.indent
  if type(indent) == "number" then
    indent = indent > 0 and string.rep(" ", indent) or nil
  elseif type(indent) ~= "string" or indent == "" then
    indent = nil
  end

  return encode_value(value, opts, indent, 0, {})
end

--- Convenience wrapper: multi-line output with 2-space indentation.
---@param value any
---@param opts? Lib.JSON.EncodeOpts # `indent` defaults to 2 here
---@return string|nil encoded
---@return string|nil err
function M.pretty(value, opts)
  opts = opts or {}
  if opts.indent == nil then
    opts = { indent = 2, sort_keys = opts.sort_keys }
  end
  return M.encode(value, opts)
end

-- The module itself is callable: `json.encode(value)` and
-- `json.encode.pretty(value)` both work.
setmetatable(M, {
  __call = function(_, value, opts)
    return M.encode(value, opts)
  end,
})

---@type Lib.JSON.Encode
return M
