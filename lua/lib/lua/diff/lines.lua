---@module 'lib.lua.diff.lines'
--- Cheap common-prefix/common-suffix line diff producing a single splice
--- region, pure Lua.

---@type LibDiffLines
local M = {}

---Compute the minimal splice region turning line array `a` into `b`.
---
---Returns `nil` if `a` and `b` are equal (same length, every element `==`).
---Otherwise returns `{ start, a_end, b_end }` — all 1-based, inclusive:
---everything before index `start` and everything after `a_end` (in `a`) /
---`b_end` (in `b`) is identical between `a` and `b`. Replacing
---`a[start..a_end]` with `b[start..b_end]` turns `a` into `b`.
---
---An empty replaced range is expressed as `a_end = start - 1` (pure
---insertion, nothing removed from `a`) or `b_end = start - 1` (pure
---deletion, nothing inserted from `b`).
---
---Worked example: `a = {"x","y","z"}`, `b = {"x","1","2","z"}`
---  -> `{ start = 2, a_end = 2, b_end = 3 }`
---  (`a[2..2] = {"y"}` is replaced by `b[2..3] = {"1","2"}`)
---@nodiscard
---@param a string[]
---@param b string[]
---@return LibDiffSpliceRegion|nil
function M.diff(a, b)
  local na, nb = #a, #b

  local prefix = 0
  local max_prefix = math.min(na, nb)
  while prefix < max_prefix and a[prefix + 1] == b[prefix + 1] do
    prefix = prefix + 1
  end

  if prefix == na and prefix == nb then
    return nil
  end

  local suffix = 0
  local max_suffix = math.min(na, nb) - prefix
  while suffix < max_suffix and a[na - suffix] == b[nb - suffix] do
    suffix = suffix + 1
  end

  return {
    start = prefix + 1,
    a_end = na - suffix,
    b_end = nb - suffix,
  }
end

return M
