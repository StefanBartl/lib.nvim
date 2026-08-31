---@module 'lib.nvim.fs.normkey'
--- Canonical, cross-platform cache/dedup key for a filesystem path.
---
--- Expands `~`, optionally resolves symlinks via `uv.fs_realpath` (default
--- on), forces forward slashes, uppercases a Windows drive letter, and
--- collapses duplicate separators — with an explicit UNC guard so a
--- `//server/share/...` prefix is never collapsed to a single slash.
---
--- `uv.fs_realpath` fails on a path that does not exist yet, and a plain
--- fallback to the input is not good enough on Windows: `$TEMP` there is
--- routinely the 8.3 short form (`C:/Users/STEFAN~1/...`), so the raw input
--- and the resolved path are *different strings for the same directory*.
--- A key that changes the moment the directory is created is not a key —
--- anything cached under it before `mkdir` can never be found after. So when
--- the full path cannot be resolved, this module resolves the nearest
--- existing ancestor and re-appends the unresolved tail.
---
--- Deliberately does **not** route through
--- `lib.nvim.cross.fs.separators.collapse_dots`: that module has a confirmed
--- gap where it does not special-case a UNC prefix (see its README) and
--- would corrupt one. This module keeps its own guarded collapse instead.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")

local uv = vim.uv or vim.loop

---The shortest prefix of `path` that is a filesystem root, and therefore the
---point above which the ancestor walk must not go.
---
---`//server/share` is one unit: neither `//server` nor `//` is a directory
---anyone can resolve, and treating them as candidates would walk a UNC path
---apart. A drive is `C:/`; a POSIX root is `/`.
---@param path string  slash-unified
---@return integer  byte length of the root prefix (0 when the path is relative)
local function root_len(path)
  local unc = path:match("^//[^/]+/[^/]+")
  if unc then
    return #unc
  end
  local drive = path:match("^%a:/")
  if drive then
    return #drive
  end
  if path:sub(1, 1) == "/" then
    return 1
  end
  return 0
end

---Resolve `path` as far as the filesystem allows.
---
---Returns `uv.fs_realpath(path)` when the whole path exists. Otherwise walks
---up until an ancestor resolves and re-appends the segments that were walked
---past, so a not-yet-created path keys the same as it will once it exists.
---Returns nil when nothing along the way resolves.
---@param path string  slash-unified, no trailing separator
---@return string|nil
local function realpath_deepest(path)
  local direct = uv.fs_realpath(path)
  if direct then
    return direct
  end

  local floor = root_len(path)
  local tail = {}
  local cur = path

  while #cur > floor do
    local slash = cur:match("^.*()/")
    if not slash or slash <= floor then
      break
    end
    table.insert(tail, 1, cur:sub(slash + 1))
    cur = cur:sub(1, slash - 1)
    if #cur <= floor then
      cur = path:sub(1, floor)
    end
    local resolved = uv.fs_realpath(cur)
    if resolved then
      return unify_slashes(resolved):gsub("/+$", "") .. "/" .. table.concat(tail, "/")
    end
  end

  return nil
end

--- `p` is deliberately optional: the guard below answers `""` for anything
--- that is not a non-empty string, and callers rely on that.
---@param p string|nil
---@param opts? Lib.Fs.NormkeyOpts
---@return string
return function(p, opts)
  if type(p) ~= "string" or p == "" then
    return ""
  end
  opts = opts or {}
  local use_real = opts.realpath ~= false

  local home = (uv.os_homedir and uv.os_homedir()) or os.getenv("HOME")
  if home then
    p = p:gsub("^~", home)
  end

  local out = p
  if use_real and uv.fs_realpath then
    -- Unify first: the walk splits on "/", and a Windows input arrives with
    -- backslashes. fs_realpath accepts either.
    local unified = unify_slashes(p)
    -- Strip a trailing separator, but never eat the root itself: "C:/" must
    -- not become "C:", which Windows reads as "the cwd on drive C".
    local floor = root_len(unified)
    local stripped = unified
    if #stripped > math.max(floor, 1) then
      stripped = stripped:gsub("(.)/+$", "%1")
    end
    out = realpath_deepest(stripped) or p
  end

  out = unify_slashes(out)
  out = drive_upper(out)

  -- Collapse duplicate slashes, but keep a UNC prefix ("//server/share") intact.
  if not out:match("^//") then
    out = out:gsub("//+", "/")
  end

  return out
end
