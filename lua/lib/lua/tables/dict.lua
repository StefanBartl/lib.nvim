---@module 'lib.lua.tables.dict'
--- Helpers for dictionary-like tables (non-array).

---@type TablesDict
local M = {}

--- Shallow copy of a dictionary.
---@generic K, V
---@param t table<K, V>
---@return table<K, V>
function M.clone(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

--- Pick subset of keys.
---@generic K, V
---@param t table<K, V>
---@param keys K[]
---@return table<K, V>
function M.pick(t, keys)
  local out = {}
  for i = 1, #keys do
    local k = keys[i]
    if t[k] ~= nil then
      out[k] = t[k]
    end
  end
  return out
end

--- Omit keys.
---@generic K, V
---@param t table<K, V>
---@param keys K[]
---@return table<K, V>
function M.omit(t, keys)
  local out = M.clone(t)
  for i = 1, #keys do
    out[keys[i]] = nil
  end
  return out
end

--- Merge dictionaries (right-biased).
---@generic K, V
---@param a table<K, V>
---@param b table<K, V>
---@return table<K, V>
function M.merge(a, b)
  local out = M.clone(a)
  for k, v in pairs(b) do
    out[k] = v
  end
  return out
end

--- Keys as array.
---@generic K, V
---@param t table<K, V>
---@return K[]
function M.keys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  ---@type K[]
  local out = { [n] = false }
  local i = 0
  for k in pairs(t) do
    i = i + 1
    out[i] = k
  end
  return out
end

--- Values as array.
---@generic K, V
---@param t table<K, V>
---@return V[]
function M.values(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  local out = { [n] = false }
  local i = 0
  for _, v in pairs(t) do
    i = i + 1
    out[i] = v
  end
  return out
end

--- Group array of items into dict of arrays by key function.
---@param xs any[]
---@param keyfn fun(v:any): string|number
---@return table<string|number, any[]>
function M.group_by(xs, keyfn)
  local out = {}
  for i = 1, #xs do
    local v = xs[i]
    local k = keyfn(v)
    local bucket = out[k]
    if bucket == nil then
      bucket = {}
      out[k] = bucket
    end
    bucket[#bucket + 1] = v
  end
  return out
end

return M
