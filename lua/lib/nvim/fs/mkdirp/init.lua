---@module 'lib.nvim.fs.mkdirp'
--- Recursive directory creation (`mkdir -p`) built purely on libuv.
---
--- Why this exists next to `vim.fn.mkdir(path, "p")`: `vim.fn.*` may not be
--- called from a *fast event context* — the callback of a `uv` timer, an
--- `fs_event` watcher, or a subprocess stdout reader. Doing so aborts with
--- `E5560: Vimscript function must not be called in a fast event context`.
--- Every call in here is `vim.uv`/`vim.loop` only: no `vim.fn`, no `vim.api`,
--- no `vim.schedule`. Safe to call from anywhere, including a spawn callback.
---
--- Semantics match `mkdir -p`: missing parents are created, an already
--- existing directory is success, and a path component that exists as a
--- *file* is an error.
---
--- See @types/init.lua for Lib.Fs.Mkdirp.

require("lib.nvim.fs.mkdirp.@types")

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

local function uv()
  return vim.uv or vim.loop
end

-- 0755 — LuaJIT has no octal literals.
local DIR_MODE = tonumber("755", 8)

---Split `path` into the part that must not be created (drive letter, UNC
---share, leading `/`) and the remaining segments to walk.
---@param path string Forward-slash normalized path
---@return string prefix Already-existing root prefix, "" when there is none
---@return string rest Remainder to split into segments
---@return boolean rooted True when the first segment must be prefixed with "/"
local function split_root(path)
  -- UNC: //server/share — neither the server nor the share can be created.
  local unc = path:match("^//[^/]+/[^/]+")
  if unc then
    return unc, path:sub(#unc + 1), true
  end

  -- Windows drive: C:/ or C: (the drive itself is never created).
  local drive = path:match("^%a:")
  if drive then
    return drive, path:sub(#drive + 1), true
  end

  -- POSIX absolute vs. relative — the only difference is the leading "/",
  -- which `gmatch("[^/]+")` would otherwise swallow.
  return "", path, path:sub(1, 1) == "/"
end

---Create `path` and any missing parent directories.
---
---Fast-event safe: uses `uv.fs_mkdir`/`uv.fs_stat` exclusively.
---@param path string Directory path to create (absolute or relative)
---@return boolean ok
---@return string|nil err Error message when `ok` is false
return function(path)
  if type(path) ~= "string" or path == "" then
    return false, "mkdirp: path must be a non-empty string"
  end

  local loop = uv()
  local normalized = unify_slashes(path)
  local prefix, rest, rooted = split_root(normalized)

  local current = prefix
  local first = true
  for segment in rest:gmatch("[^/]+") do
    -- Skip no-op components so "a/./b" and a trailing "/" behave.
    if segment ~= "." then
      if first and prefix == "" and not rooted then
        current = segment
      else
        current = current .. "/" .. segment
      end
      first = false

      local ok = loop.fs_mkdir(current, DIR_MODE)
      if not ok then
        -- `fs_mkdir` failing is only fatal when the path is not already a
        -- directory: EEXIST on a directory is the `-p` success case, and a
        -- concurrent creator racing us lands here too.
        local stat = loop.fs_stat(current)
        if not stat then
          return false, "mkdirp: cannot create " .. current
        end
        if stat.type ~= "directory" then
          return false, "mkdirp: not a directory: " .. current
        end
      end
    end
  end

  if first then
    -- No creatable segment at all ("/", "C:/", "//server/share"). Those roots
    -- are not ours to create, so this is success iff they already exist.
    local stat = loop.fs_stat(current == "" and "/" or current)
    if stat and stat.type == "directory" then
      return true, nil
    end
    return false, "mkdirp: no directory component in " .. path
  end

  return true, nil
end
