---@module 'lib.lua.tables.set'
--- Simple generic Set<T> implemented as table<T, true> with helper functions.

---@type TablesSet
local M = {}

--- Create a set from an array.
---@generic T
---@param xs T[]
---@return table<T, true>
function M.from_array(xs)
  local s = {}
  for i = 1, #xs do
    s[xs[i]] = true
  end
  return s
end

--- Convert set back to array (no order guarantee).
---@generic T
---@param s table<T, true>
---@return T[]
function M.to_array(s)
  ---@type T[]
  local out = {}
  local i = 0
  for k in pairs(s) do
    i = i + 1
    out[i] = k
  end
  return out
end

--- Add a value to the set.
---@generic T
---@param s table<T, true>
---@param v T
function M.add(s, v)
  s[v] = true
end

--- Add multiple values from an array.
---@generic T
---@param s table<T, true>
---@param xs T[]
function M.add_all(s, xs)
  for i = 1, #xs do
    s[xs[i]] = true
  end
end

--- Remove a value from the set.
---@generic T
---@param s table<T, true>
---@param v T
function M.remove(s, v)
  s[v] = nil
end

--- Remove multiple values from an array.
---@generic T
---@param s table<T, true>
---@param xs T[]
function M.remove_all(s, xs)
  for i = 1, #xs do
    s[xs[i]] = nil
  end
end

--- Clear a set in-place.
---@generic T
---@param s table<T, true>
function M.clear(s)
  for k in pairs(s) do
    s[k] = nil
  end
end

--- Check membership.
---@generic T
---@param s table<T, true>
---@param v T
---@return boolean
function M.has(s, v)
  return s[v] == true
end

--- Number of elements.
---@generic T
---@param s table<T, true>
---@return integer
function M.size(s)
  local n = 0
  for _ in pairs(s) do
    n = n + 1
  end
  return n
end

--- Shallow copy of a set.
---@generic T
---@param s table<T, true>
---@return table<T, true>
function M.copy(s)
  local out = {}
  for k in pairs(s) do
    out[k] = true
  end
  return out
end

--- Build a set from the keys of a table.
---@generic K, V
---@param t table<K, V>
---@return table<K, true>
function M.from_keys(t)
  local out = {} ---@type table<K, true>
  for k, _ in pairs(t) do
    out[k] = true
  end
  return out
end

--- Union of two sets (new set).
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return table<T, true>
function M.union(a, b)
  local out = {}
  for k in pairs(a) do
    out[k] = true
  end
  for k in pairs(b) do
    out[k] = true
  end
  return out
end

--- Intersection of two sets (new set).
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return table<T, true>
function M.intersection(a, b)
  local out = {}
  -- Iterate smaller set for performance
  local sa, sb = M.size(a), M.size(b)
  if sa <= sb then
    for k in pairs(a) do
      if b[k] then
        out[k] = true
      end
    end
  else
    for k in pairs(b) do
      if a[k] then
        out[k] = true
      end
    end
  end
  return out
end

--- Difference (a \ b): elements in a that are not in b (new set).
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return table<T, true>
function M.difference(a, b)
  local out = {}
  for k in pairs(a) do
    if not b[k] then
      out[k] = true
    end
  end
  return out
end

--- Symmetric difference: elements in a or b but not both (new set).
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return table<T, true>
function M.symmetric_difference(a, b)
  local out = {}
  for k in pairs(a) do
    if not b[k] then
      out[k] = true
    end
  end
  for k in pairs(b) do
    if not a[k] then
      out[k] = true
    end
  end
  return out
end

--- Subset test: a ⊆ b.
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return boolean
function M.is_subset(a, b)
  for k in pairs(a) do
    if not b[k] then
      return false
    end
  end
  return true
end

--- Superset test: a ⊇ b.
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return boolean
function M.is_superset(a, b)
  for k in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

--- Equality test (same elements).
---@generic T
---@param a table<T, true>
---@param b table<T, true>
---@return boolean
function M.equals(a, b)
  local sa, sb = M.size(a), M.size(b)
  if sa ~= sb then
    return false
  end
  for k in pairs(a) do
    if not b[k] then
      return false
    end
  end
  return true
end

--- Filter set by predicate; returns a new set.
---@generic T
---@param s table<T, true>
---@param pred fun(value:T):boolean
---@return table<T, true>
function M.filter(s, pred)
  local out = {}
  for k in pairs(s) do
    if pred(k) then
      out[k] = true
    end
  end
  return out
end

--- Map set to a new set of possibly different element type U.
--- Note: collisions (two T mapping to same U) are naturally deduplicated.
---@generic T, U
---@param s table<T, true>
---@param fn fun(value:T):U
---@return table<U, true>
function M.map(s, fn)
  local out = {}
  for k in pairs(s) do
    out[fn(k)] = true
  end
  return out
end

--- Iterator over set elements (no guaranteed order).
---@generic T
---@param s table<T, true>
---@return fun():T
function M.iter(s)
  local next_fn, tab, key = next, s, nil
  return function()
    key = next_fn(tab, key)
    return key
  end
end

return M
