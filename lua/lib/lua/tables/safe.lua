---@module 'lib.lua.tables.safe'
--- Safe, defensive mutators and iteration guards for tables.

---@type LibTablesSafe
local S = {}

---@nodiscard
---@generic T
---@param list T[]|nil
---@return T[]
function S.ensure_list(list)
  if type(list) == "table" then
    return list
  end
  return {}
end

---@nodiscard
---@param t table|nil
---@return table
function S.ensure_table(t)
  if type(t) == "table" then
    return t
  end
  return {}
end

---@param list any[]
---@param v any
---@return integer new_len
function S.push(list, v)
  list[#list + 1] = v
  return #list
end

---@param list any[]
---@return any|nil v
function S.pop(list)
  local n = #list
  if n == 0 then
    return nil
  end
  local v = list[n]
  list[n] = nil
  return v
end

---@param list any[]
---@param idx integer
---@param v any
---@return boolean
function S.insert_at(list, idx, v)
  local n = #list
  if idx < 1 or idx > n + 1 then
    return false
  end
  for i = n, idx, -1 do
    list[i + 1] = list[i]
  end
  list[idx] = v
  return true
end

---@param list any[]
---@param idx integer
---@return boolean
function S.remove_at(list, idx)
  local n = #list
  if idx < 1 or idx > n then
    return false
  end
  for i = idx, n - 1 do
    list[i] = list[i + 1]
  end
  list[n] = nil
  return true
end

---@nodiscard
---@param t table
---@return table snapshot
function S.snapshot_shallow(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

---@nodiscard
---@generic T
---@param list T[]
---@return fun():integer,T
function S.safe_ipairs(list)
  local n = #list
  local i = 0
  return function()
    i = i + 1
    if i <= n then
      return i, list[i]
    end
  end
end

return S
