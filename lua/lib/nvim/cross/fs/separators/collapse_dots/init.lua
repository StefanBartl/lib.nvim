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
---
--- The public return function is a thin orchestrator: it only wires together
--- the small, independently-testable pure helpers below. Each step (validate,
--- unify, detect root, split, collapse, join) can be modified or debugged in
--- isolation without touching the others.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

--- Guard: the input must be a string. Returns it unchanged for chaining.
---@param path string
---@return string
local function validate(path)
  assert(
    type(path) == "string",
    "[lib.nvim.cross.fs.separators.collapse_dots] parameter 'path' must be type of string, but is " .. type(path)
  )
  return path
end

--- Detect a POSIX root prefix: '/' for absolute paths, '' otherwise.
---@param path string  # forward-slash form
---@return string root  # "/" or ""
local function detect_root(path)
  return path:match("^/") and "/" or ""
end

--- Split a forward-slash path into its non-empty segments (drops repeated '/').
---@param path string  # forward-slash form
---@return string[] segments
local function split_segments(path)
  local segments = {}
  for seg in path:gmatch("[^/]+") do
    segments[#segments + 1] = seg
  end
  return segments
end

--- True when a segment is a bare Windows drive prefix ('C:', 'e:').
---@param seg string
---@return boolean
local function is_drive_prefix(seg)
  return seg:match("^%a:$") ~= nil
end

--- Reduce raw segments into a collapsed stack, applying the '.'/'..' rules.
--- Pure: builds and returns a fresh list, never mutates the input.
---@param segments string[]
---@param has_root boolean  # true when the path started at a POSIX root '/'
---@return string[] collapsed
local function collapse_segments(segments, has_root)
  local out = {}
  for _, seg in ipairs(segments) do
    if seg == "." then
      -- current dir: drop
    elseif seg == ".." then
      local top = out[#out]
      if top and is_drive_prefix(top) then
        -- at a Windows drive root ('C:'): '..' is a no-op, drop it
      elseif #out > 0 and top ~= ".." then
        table.remove(out)
      elseif not has_root then
        -- relative path climbing above its base: keep the '..'
        out[#out + 1] = seg
      end
      -- POSIX absolute at root: a '..' is a no-op (drop it)
    else
      out[#out + 1] = seg
    end
  end
  return out
end

--- Reassemble a root marker and collapsed segments into a path string.
---@param root string  # "/" or ""
---@param segments string[]
---@return string
local function join(root, segments)
  return root .. table.concat(segments, "/")
end

---@param path string
---@return string
return function(path)
  local unified = unify_slashes(validate(path))
  local root    = detect_root(unified)
  local raw     = split_segments(unified)
  local kept    = collapse_segments(raw, root ~= "")
  return join(root, kept)
end
