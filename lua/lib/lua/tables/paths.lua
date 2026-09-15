---@module 'lib.lua.tables.paths'
--- Recursive path-flattening for nested tables: turns a JSON/YAML/XML-shaped
--- Lua value into a flat `{ path, value }[]` list, one entry per leaf.
---
--- Pure Lua, no `vim` API. This is a different operation from
--- `lib.lua.tables.array`'s `flatten` (which flattens one level of *array*
--- nesting) — flattening *paths through nested maps/arrays* down to leaves.
--- Exposed on the aggregator as `tables.path_flatten` (not `tables.paths.*`)
--- to match this module's existing flat-namespace-with-prefix convention
--- (`dict_*`, `set_*`) instead of introducing a nested sub-table.

local M = {}

-- Lib.Tables.Paths.FlattenOpts is declared once, in @types/paths.lua.

local DEFAULT_SEP = "."
local DEFAULT_MAX_DEPTH = 64

---@internal
--- Contiguous positive integer keys starting at 1 (Lua array semantics).
---@param v any
---@return boolean
local function is_array_like(v)
  if type(v) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(v) do
    i = i + 1
    if v[i] == nil then
      return false
    end
  end
  return true
end

---@internal
--- Recursive worker. Appends `{path, value}` leaves onto `out`.
---@param value any
---@param prefix string
---@param sep string
---@param depth integer
---@param max_depth integer
---@param out {path: string, value: any}[]
---@return string|nil err
local function walk(value, prefix, sep, depth, max_depth, out)
  if depth > max_depth then
    return ("max depth (%d) exceeded at %q"):format(max_depth, prefix)
  end

  if type(value) ~= "table" or next(value) == nil then
    -- Scalars, and empty tables (object or array, indistinguishable) are
    -- both leaves -- otherwise an empty nested object/array would vanish
    -- from the output instead of appearing as `path = {}`.
    out[#out + 1] = { path = prefix, value = value }
    return nil
  end

  if is_array_like(value) then
    for i = 1, #value do
      local child_path = prefix == "" and tostring(i) or (prefix .. sep .. tostring(i))
      local err = walk(value[i], child_path, sep, depth + 1, max_depth, out)
      if err then
        return err
      end
    end
    return nil
  end

  local keys = {}
  for k in pairs(value) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  for _, k in ipairs(keys) do
    local child_path = prefix == "" and tostring(k) or (prefix .. sep .. tostring(k))
    local err = walk(value[k], child_path, sep, depth + 1, max_depth, out)
    if err then
      return err
    end
  end
  return nil
end

--- Flatten a nested Lua value into `{path, value}[]`, one entry per leaf.
--- Object keys are visited in sorted order for deterministic output; array
--- indices keep their natural 1..n order.
---@nodiscard
---@param value any
---@param opts? Lib.Tables.Paths.FlattenOpts
---@return {path: string, value: any}[]|nil items
---@return string|nil err
function M.flatten(value, opts)
  opts = opts or {}
  local sep = opts.sep
  if type(sep) ~= "string" or sep == "" then
    sep = DEFAULT_SEP
  end
  local max_depth = opts.max_depth
  if type(max_depth) ~= "number" or max_depth < 1 then
    max_depth = DEFAULT_MAX_DEPTH
  end

  local out = {}
  local err = walk(value, "", sep, 0, max_depth, out)
  if err then
    return nil, err
  end
  return out, nil
end

---@type Lib.Tables.Paths
return M
