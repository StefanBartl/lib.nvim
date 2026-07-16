---@module 'lib.nvim.fs.relpath'
--- Compute `path` relative to `base`.
---
--- Both arguments are made absolute and normalized to forward slashes, so this
--- works with mixed separators on Windows. `base` is treated as a directory:
--- when `path` lives under it, the base prefix (and the separating slash) is
--- stripped. When it does not, `..` segments climb from `base` to the nearest
--- common ancestor and back down to `path` (POSIX-style), unless the two
--- paths don't share a root at all (e.g. different Windows drive letters),
--- in which case the absolute `path` is returned unchanged since no relative
--- form exists. A `path` equal to `base` yields ".".
---
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

  -- Windows drive letters (or, in principle, differing UNC hosts) mean there
  -- is no relative path between the two at all; POSIX paths always share the
  -- single "/" root, so this only ever bails out on Windows.
  local function root_of(p)
    return p:match("^(%a:)/") or (p:sub(1, 1) == "/" and "/") or ""
  end
  if root_of(base) ~= root_of(path) then
    return path
  end

  local base_segs, path_segs = {}, {}
  for seg in base:gmatch("[^/]+") do base_segs[#base_segs + 1] = seg end
  for seg in path:gmatch("[^/]+") do path_segs[#path_segs + 1] = seg end

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
