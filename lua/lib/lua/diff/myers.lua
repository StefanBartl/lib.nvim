---@module 'lib.lua.diff.myers'
--- Correct full line-diff producing an ordered edit script, pure Lua.
---
--- Implemented as a straightforward O(n*m) dynamic-programming LCS diff
--- (build the LCS length table, then backtrack to emit equal/insert/delete
--- ops) rather than the greedy O(ND) Myers algorithm — DP is simpler to get
--- right and perfectly adequate for typical buffer/line-array sizes.

---@type LibDiffMyers
local M = {}

---Diff two line arrays into an ordered edit script.
---
---Worked examples (hand-verified):
---  `diff({"a","b","c"}, {"a","x","c"})`
---    -> `equal(a), delete(b), insert(x), equal(c)`
---  `diff({}, {"a"})` -> `insert(a)`
---  `diff({"a"}, {})` -> `delete(a)`
---  `diff({"a","b"}, {"a","b"})` -> `equal(a), equal(b)`
---(Order of delete/insert for a pure substitution is a convention, not a
---correctness requirement; this implementation always emits delete before
---insert for one differing line.)
---@nodiscard
---@param a string[]
---@param b string[]
---@return LibDiffOp[]
function M.diff(a, b)
  local na, nb = #a, #b

  -- lcs[i][j] = length of the LCS of a[1..i] and b[1..j]
  ---@type integer[][]
  local lcs = {}
  for i = 0, na do
    lcs[i] = {}
    lcs[i][0] = 0
  end
  for j = 0, nb do
    lcs[0][j] = 0
  end

  for i = 1, na do
    for j = 1, nb do
      if a[i] == b[j] then
        lcs[i][j] = lcs[i - 1][j - 1] + 1
      else
        local up, left = lcs[i - 1][j], lcs[i][j - 1]
        lcs[i][j] = up >= left and up or left
      end
    end
  end

  -- Backtrack from (na, nb) to (0, 0), building the script in reverse.
  ---@type LibDiffOp[]
  local reversed = {}
  local i, j = na, nb
  while i > 0 or j > 0 do
    if i > 0 and j > 0 and a[i] == b[j] then
      reversed[#reversed + 1] = { op = "equal", value = a[i] }
      i = i - 1
      j = j - 1
    elseif j > 0 and (i == 0 or lcs[i][j - 1] >= lcs[i - 1][j]) then
      reversed[#reversed + 1] = { op = "insert", value = b[j] }
      j = j - 1
    else
      reversed[#reversed + 1] = { op = "delete", value = a[i] }
      i = i - 1
    end
  end

  ---@type LibDiffOp[]
  local script = {}
  for k = #reversed, 1, -1 do
    script[#script + 1] = reversed[k]
  end

  return script
end

return M
