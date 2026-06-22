---@module 'lib.lua.tables.functional'
--- Functional-style helpers over arrays: map, filter, reduce, etc.
--- All functions are pure and return new arrays where applicable.

---@type LibTablesFn
local F = {}

---@nodiscard
---@generic T,U
---@param list T[]
---@param fn fun(item:T, index:integer):U
---@return U[]
function F.map(list, fn)
  local out = { [#list] = false }
  for i = 1, #list do
    out[i] = fn(list[i], i)
  end
  return out
end

---@nodiscard
---@generic T
---@param list T[]
---@param pred fun(item:T, index:integer):boolean
---@return T[]
function F.filter(list, pred)
  local out = {}
  for i = 1, #list do
    local it = list[i]
    if pred(it, i) then
      out[#out + 1] = it
    end
  end
  return out
end

---@nodiscard
---@generic T,U
---@param list T[]
---@param init U
---@param fn fun(acc:U, item:T, index:integer):U
---@return U
function F.reduce(list, init, fn)
  local acc = init
  for i = 1, #list do
    acc = fn(acc, list[i], i)
  end
  return acc
end

---@nodiscard
---@generic T
---@param list T[]
---@param pred fun(item:T, index:integer):boolean
---@return T|nil
function F.find(list, pred)
  for i = 1, #list do
    local it = list[i]
    if pred(it, i) then
      return it
    end
  end
  return nil
end

---@nodiscard
---@generic T
---@param list T[]
---@param pred fun(item:T):boolean
---@return boolean
function F.any(list, pred)
  for i = 1, #list do
    if pred(list[i]) then
      return true
    end
  end
  return false
end

---@nodiscard
---@generic T
---@param list T[]
---@param pred fun(item:T):boolean
---@return boolean
function F.all(list, pred)
  for i = 1, #list do
    if not pred(list[i]) then
      return false
    end
  end
  return true
end

---@nodiscard
---@generic T,U
---@param list T[]
---@param fn fun(item:T):U[]
---@return U[]
function F.flat_map(list, fn)
  local out = {}
  for i = 1, #list do
    local r = fn(list[i])
    if type(r) == "table" then
      for j = 1, #r do
        out[#out + 1] = r[j]
      end
    end
  end
  return out
end

return F
