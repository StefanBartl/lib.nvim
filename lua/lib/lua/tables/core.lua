---@module 'lib.lua.tables.core'
--- Core table utilities: shape checks, copies, key/value helpers, merging, slicing.
--- Design:
---   * Pure functions unless explicitly marked as mutating.
---   * No globals; defensive parameter checks.
---   * EmmyLua-typed for strong LuaLS hints.

---@type LibTablesCore
local M = {}

---@nodiscard
---@param t any
---@return boolean
function M.is_table(t)
  return type(t) == "table"
end

---@nodiscard
---@param t any
---@return boolean
function M.is_array(t)
  -- Heuristic: consecutive integer keys starting at 1 with #t matching
  if type(t) ~= "table" then
    return false
  end
  local n = #t
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  -- allow mixed tables -> reject when extra non-integer keys exist
  for k, _ in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      if k > n then
        return false
      end
    end
  end
  return true
end

---@nodiscard
---@generic T: table
---@param t T
---@return T
function M.shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

---@nodiscard
---@generic T: table
---@param t T
---@return T
function M.deep_copy(t)
  local function _copy(v, seen)
    if type(v) ~= "table" then
      return v
    end
    if seen[v] then
      return seen[v]
    end
    local r = {}
    seen[v] = r
    for k, x in pairs(v) do
      r[_copy(k, seen)] = _copy(x, seen)
    end
    return r
  end
  ---@type table<any, any>
  local seen = {}
  local out = _copy(t, seen)
  return out
end

---@nodiscard
---@param t table
---@return string[]
function M.keys(t)
  ---@type string[]
  local out = {}
  for k, _ in pairs(t) do
    if type(k) == "string" then
      out[#out + 1] = k
    end
  end
  return out
end

---@nodiscard
---@param t table
---@return any[]
function M.values(t)
  ---@type any[]
  local out = {}
  for _, v in pairs(t) do
    out[#out + 1] = v
  end
  return out
end

---@nodiscard
---@param list string[]
---@return table<string, true>
function M.invert_set(list)
  local set = {} ---@type table<string, true>
  for i = 1, #list do
    local s = list[i]
    if type(s) == "string" then
      set[s] = true
    end
  end
  return set
end

---@nodiscard
---@param t table
---@param pick_keys string[]
---@return table
function M.pick(t, pick_keys)
  local out = {}
  for i = 1, #pick_keys do
    local k = pick_keys[i]
    out[k] = t[k]
  end
  return out
end

---@nodiscard
---@param t table
---@param omit_keys string[]
---@return table
function M.omit(t, omit_keys)
  local out = M.shallow_copy(t)
  for i = 1, #omit_keys do
    out[omit_keys[i]] = nil
  end
  return out
end

---@nodiscard
---@param dst table
---@param src table
---@return table
function M.merge_shallow(dst, src)
  for k, v in pairs(src) do
    dst[k] = v
  end
  return dst
end

---@param dst table
---@param src table
---@return table
function M.merge_deep(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      M.merge_deep(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

---@nodiscard
---@param list any[]
---@return any[]
function M.dedup_list(list)
  local seen = {} ---@type table<any, boolean>
  ---@type any[]
  local out = {}
  for i = 1, #list do
    local v = list[i]
    if not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  return out
end

---Find indices to remove so only the first occurrence per key survives.
---Pure: does not mutate `list`. Indices are returned in ascending order,
---suitable for removal from the end backwards.
---@nodiscard
---@generic T
---@param list T[]
---@param key_fn fun(item: T): any
---@return integer[] indices
function M.dedup_indices(list, key_fn)
  local seen = {} ---@type table<any, boolean>
  ---@type integer[]
  local out = {}
  for i = 1, #list do
    local k = key_fn(list[i])
    if seen[k] then
      out[#out + 1] = i
    else
      seen[k] = true
    end
  end
  return out
end

---@nodiscard
---@generic T
---@param list T[]
---@param i integer
---@param j integer|nil
---@return T[]
function M.slice(list, i, j)
  local n = #list
  local a = (i < 0) and (n + i + 1) or i
  local b = j and ((j < 0) and (n + j + 1) or j) or n
  if a < 1 then
    a = 1
  end
  if b > n then
    b = n
  end
  if a > b then
    return {}
  end

  local out = { [b - a + 1] = false }
  for k = a, b do
    out[k - a + 1] = list[k]
  end
  return out
end

---@nodiscard
---@generic T
---@param list T[]
---@param v T
---@return boolean
function M.unique_push(list, v)
  for i = 1, #list do
    if list[i] == v then
      return false
    end
  end
  list[#list + 1] = v
  return true
end

---@nodiscard
---@generic T
---@param list T[]
---@param cmp fun(a:T,b:T):boolean
---@param x T
---@return integer index
---@return boolean found
function M.binary_search(list, cmp, x)
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local v = list[mid]
    if v == x then
      return mid, true
    end
    if cmp(v, x) then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return lo, false
end

---@nodiscard
---@generic T
---@param list T[]
---@param key fun(item:T):K
---@return table<K, T[]>
function M.group_by(list, key)
  local out = {}
  for i = 1, #list do
    local it = list[i]
    local k = key(it)
    local g = out[k]
    if g == nil then
      g = {}
      out[k] = g
    end
    g[#g + 1] = it
  end
  return out
end

---@nodiscard
---@generic T
---@param list T[]
---@param pred fun(item:T):boolean
---@return T[] pass
---@return T[] fail
function M.partition(list, pred)
  local pass = {}
  local fail = {}
  for i = 1, #list do
    local it = list[i]
    if pred(it) then
      pass[#pass + 1] = it
    else
      fail[#fail + 1] = it
    end
  end
  return pass, fail
end

---@nodiscard
---@generic T,K
---@param list T[]
---@param key fun(item:T):K
---@return table<K, integer>
function M.count_by(list, key)
  local out = {} ---@type table<K, integer>
  for i = 1, #list do
    local k = key(list[i])
    out[k] = (out[k] or 0) + 1
  end
  return out
end

return M
