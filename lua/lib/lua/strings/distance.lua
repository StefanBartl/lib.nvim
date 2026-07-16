---@module 'lib.lua.strings.distance'
--- Levenshtein edit distance and normalized similarity, pure Lua.

local M = {}

---Levenshtein edit distance between two strings.
---@param a string
---@param b string
---@return integer
function M.levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then
    return lb
  end
  if lb == 0 then
    return la
  end

  local prev = {} ---@type integer[]
  local cur = {} ---@type integer[]
  for j = 0, lb do
    prev[j] = j
  end

  for i = 1, la do
    cur[0] = i
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = (ca == b:byte(j)) and 0 or 1
      cur[j] = math.min(
        prev[j] + 1, -- deletion
        cur[j - 1] + 1, -- insertion
        prev[j - 1] + cost -- substitution
      )
    end
    prev, cur = cur, prev
  end

  return prev[lb]
end

---Normalized similarity in [0, 1]: 1 = identical, 0 = completely different.
---@param a string
---@param b string
---@return number
function M.similarity(a, b)
  local max_len = math.max(#a, #b)
  if max_len == 0 then
    return 1
  end
  return 1 - (M.levenshtein(a, b) / max_len)
end

return M
