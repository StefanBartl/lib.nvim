---@module 'lib.nvim.fs.relpath'
--- Compute `path` relative to `base`.
---
--- Both arguments are made absolute and normalized to forward slashes, so this
--- works with mixed separators on Windows. `base` is treated as a directory:
--- when `path` lives under it, the base prefix (and the separating slash) is
--- stripped. When it does not, `..` segments climb from `base` to the nearest
--- common ancestor and back down to `path` (POSIX-style), unless the two
--- paths don't share a root at all (e.g. genuinely different Windows drive
--- letters -- `C:` vs `D:`, not just a case difference: `c:` and `C:` name
--- the same drive and are treated as sharing a root), in which case the
--- absolute `path` is returned unchanged since no relative form exists. A
--- `path` equal to `base` yields ".".
---
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")

---@param path string
---@param base string
---@return string
return function(path, base)
  base = vim.fn.fnamemodify(base, ":p"):gsub("\\", "/"):gsub("/+$", "")
  path = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/"):gsub("/+$", "")
  if path == base then
    return "."
  end
  if path:sub(1, #base + 1) == base .. "/" then
    return path:sub(#base + 2)
  end

  -- Every comparison from here on runs against a drive-letter-folded copy:
  -- "c:" and "C:" name the same Windows drive, so `base`/`path` differing
  -- only in that one letter's case must not be read as "no shared root" (the
  -- `root_of` check below) or as "the drive segment itself never matches"
  -- (the segment walk after it). `drive_upper` only touches a leading drive
  -- prefix -- same helper `lib.nvim.fs.normkey` uses for this exact reason
  -- -- so `#base_cmp == #base` always holds and slicing the ORIGINAL `path`
  -- at an offset found in `path_cmp` still lands on the right byte, keeping
  -- every returned segment's case exactly as the caller passed it in.
  local base_cmp, path_cmp = drive_upper(base), drive_upper(path)

  -- Windows drive letters (or, in principle, differing UNC hosts) mean there
  -- is no relative path between the two at all; POSIX paths always share the
  -- single "/" root, so this only ever bails out on Windows.
  ---@internal
  local function root_of(p)
    return p:match("^(%a:)/") or (p:sub(1, 1) == "/" and "/") or ""
  end
  if root_of(base_cmp) ~= root_of(path_cmp) then
    return path
  end

  local base_segs, path_segs = {}, {}
  for seg in base_cmp:gmatch("[^/]+") do
    base_segs[#base_segs + 1] = seg
  end
  for seg in path_cmp:gmatch("[^/]+") do
    path_segs[#path_segs + 1] = seg
  end

  local i = 1
  while base_segs[i] and path_segs[i] and base_segs[i] == path_segs[i] do
    i = i + 1
  end

  local parts = {}
  for _ = i, #base_segs do
    parts[#parts + 1] = ".."
  end
  for j = i, #path_segs do
    parts[#parts + 1] = path_segs[j]
  end

  return #parts > 0 and table.concat(parts, "/") or "."
end
