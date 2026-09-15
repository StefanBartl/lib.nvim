---@module 'lib.lua.null'
--- A single canonical "null" sentinel, shared by every `lib.lua.*` format
--- module (`json`, `yaml`, and `xml` once it exists) as the one Lua-value
--- representation of "this key/element is explicitly null", distinct from
--- Lua's own `nil` (which cannot be stored as a table value at all --
--- `t[k] = nil` removes the key instead of recording anything).
---
--- Using one shared marker instead of a per-format one is what makes
--- cross-format conversion correct: a null decoded from JSON and re-encoded
--- as YAML needs to be recognized as null by the YAML encoder too, not just
--- the JSON one that produced it. `lib.nvim.json.decode` normalizes
--- `vim.json.decode`'s own `vim.NIL` sentinel into this marker for exactly
--- that reason -- see that module's doc comment.

local M = {}

--- The sentinel itself. Identity-compared (`==`), never copied by value.
---@type table
M.NULL = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

--- Whether `v` is the shared null sentinel.
---@param v any
---@return boolean
function M.is_null(v)
  return v == M.NULL
end

---@type Lib.Lua.Null
return M
