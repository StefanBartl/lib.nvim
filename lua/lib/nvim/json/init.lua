---@module 'lib.nvim.json'
--- Decode/encode arbitrary JSON strings (not just files — see
--- `lib.nvim.fs.json` for the file-backed counterpart this module now
--- backs). Decoding uses Neovim's built-in `vim.json.decode`:
--- `lib.lua.json` only exposes an encoder and array-shape decode
--- *helpers*, not a general JSON-string parser, and this module lives in
--- the `lib.nvim` (editor-adapter) namespace where `vim.json` is always
--- available. Encoding delegates to `lib.lua.json.encode`, the pure-Lua
--- encoder, so encoded output is identical inside and outside Neovim.
---
---```lua
--- local json = require("lib.nvim.json")
---
--- local tbl, err = json.decode('{"a":1}')
--- local str, err2 = json.encode({ a = 1 })
---```

require("lib.nvim.json.@types")

local lua_json = require("lib.lua.json")
local null = require("lib.lua.null")

local M = {}

-- Matches `lib.lua.tables.path_flatten`'s own `max_depth` default -- without
-- this, a pathologically deep (but acyclic) decoded value would overflow the
-- Lua call stack here instead of failing cleanly with `nil, err`.
local MAX_NORMALIZE_DEPTH = 64

---@internal
--- Recursively replace `vim.json.decode`'s own `vim.NIL` sentinel with the
--- shared `lib.lua.null.NULL` marker, so downstream consumers (encoders,
--- `lib.lua.tables.path_flatten` callers, cross-format conversion) work
--- against one Lua-value IR with no nvim-specific artifact leaking into it.
--- `vim.json.decode` never produces cycles, so no cycle guard is needed --
--- only a depth guard (`M.decode` below turns the resulting `error()` into
--- the same `nil, err` shape as any other decode failure).
---
--- The depth guard raises at level 0 **on purpose**: this message is not a
--- crash report, it is the `err` half of `M.decode`'s `(value, err)` pair and
--- ends up verbatim in a consumer's user-facing notification. At the default
--- level 1 Lua prefixes it with this file's absolute path and line number,
--- which reads like a plugin crash, names a file no user can act on, and
--- leaks the developer's filesystem layout. `vim.json.decode`'s own failures
--- arrive from C without such a prefix, so level 0 is what makes both decode
--- failure modes look alike.
---@param value any
---@param depth integer
---@return any
local function normalize_null(value, depth)
  if depth > MAX_NORMALIZE_DEPTH then
    error(
      ("max nesting depth (%d) exceeded while normalizing JSON null values"):format(
        MAX_NORMALIZE_DEPTH
      ),
      0
    )
  end
  if value == vim.NIL then
    return null.NULL
  end
  if type(value) ~= "table" then
    return value
  end
  for k, v in pairs(value) do
    value[k] = normalize_null(v, depth + 1)
  end
  return value
end

---Decode a JSON string into a Lua value.
---@param str string
---@return any decoded
---@return string|nil err
function M.decode(str)
  local ok, decoded_or_err = pcall(vim.json.decode, str)
  if not ok then
    return nil, "invalid JSON: " .. tostring(decoded_or_err)
  end
  local nok, normalized_or_err = pcall(normalize_null, decoded_or_err, 0)
  if not nok then
    return nil, "invalid JSON: " .. tostring(normalized_or_err)
  end
  return normalized_or_err, nil
end

---JSON-encode `value`. Delegates to `lib.lua.json.encode`.
---@param value any
---@param opts? Lib.JSON.EncodeOpts
---@return string|nil encoded
---@return string|nil err
function M.encode(value, opts)
  return lua_json.encode(value, opts)
end

---@type Lib.Nvim.Json
return M
