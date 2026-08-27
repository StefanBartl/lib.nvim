---@module 'lib.lua.config'
--- Pure helpers for the "defaults + user overrides" config store pattern:
--- the `setup(opts)` / `get(path)` pair almost every plugin's `config` module
--- implements.
---@description
--- Extracted from **two** byte-identical copies: cascade.nvim's and
--- spotlight.nvim's `config/init.lua` each had their own `deep_merge` and
--- `M.get`.
---
--- `deep_merge` here is deliberately not `lib.lua.tables.core.deep_merge`:
--- that one mutates `dst` in place and recurses into *every* nested table,
--- including list-like ones. A default `{ groups = { "a", "b", "c" } }`
--- overridden with `{ groups = { "x" } }` would then keep `"b"` and `"c"`
--- behind index 1's new value — exactly the array-merge surprise a config
--- store must not have, since it silently keeps stale defaults a user
--- explicitly tried to replace. This version copies `base` instead of
--- mutating it, and replaces a list-like table (per
--- `lib.lua.tables.core.is_array`) wholesale rather than recursing into it.

local tables = require("lib.lua.tables.core")

local M = {}

---Recursively merge `override` into a copy of `base`. Neither argument is
---mutated. A value that is a list-like table (checked on the *override*
---side) is replaced wholesale rather than merged element-by-element, so
---overriding e.g. `cycle.groups` fully redefines it instead of inheriting
---leftover defaults past the override's length.
---@param base table
---@param override table
---@return table
function M.deep_merge(base, override)
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(out[k]) == "table" and not tables.is_array(v) then
      out[k] = M.deep_merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

---Read a value out of `tbl` by dot-separated `path`, e.g. `get(opts, "a.b.c")`.
---A missing intermediate key, or a non-table where a table was expected,
---returns `nil` rather than erroring.
---@param tbl table
---@param path string?
---@return any
function M.get(tbl, path)
  if type(path) ~= "string" then
    return nil
  end
  local node = tbl
  for key in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return node
end

---@type Lib.Config
return M
