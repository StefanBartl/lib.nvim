---@module 'lib.nvim.cross.fs.separators.collapse_dots'
--- Lexically collapse '.'/'..' segments and repeated separators in a path.
--- Pure string transform: no `~`/env expansion, no disk access, no symlink
--- resolution. Complements the sibling separator helpers:
---   * unify_slashes -> '\' to '/'            (pure, direction fixed)
---   * normalize     -> to the OS-native sep  (pure, direction per-OS)
---   * collapse_dots -> simplify segments     (pure, segment-level)
--- Works in forward-slash space (unifies the input first) and returns
--- forward-slash form. Keeps a leading '/' (POSIX root) and a 'C:' drive
--- prefix intact, and never pops past either of them.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

---@param path string
---@return string
return function(path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.separators.collapse_dots] parameter 'path' must be type of string, but is " .. type(path)
  )

  path = unify_slashes(path)
  local leading = path:match("^/") and "/" or ""
  local segs = {}
  for seg in path:gmatch("[^/]+") do
    if seg == "." then
      -- drop
    elseif seg == ".." then
      local top = segs[#segs]
      if top and top:match("^%a:$") then
        -- at a Windows drive root ('C:'): '..' is a no-op, drop it
      elseif #segs > 0 and top ~= ".." then
        table.remove(segs)
      elseif leading == "" then
        -- relative path climbing above its base: keep the '..'
        table.insert(segs, seg)
      end
      -- POSIX absolute at root: a '..' is a no-op (drop it)
    else
      table.insert(segs, seg)
    end
  end
  return leading .. table.concat(segs, "/")
end
