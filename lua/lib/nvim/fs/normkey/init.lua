---@module 'lib.nvim.fs.normkey'
--- Canonical, cross-platform cache/dedup key for a filesystem path.
---
--- Expands `~`, optionally resolves symlinks via `uv.fs_realpath` (default
--- on), forces forward slashes, uppercases a Windows drive letter, and
--- collapses duplicate separators — with an explicit UNC guard so a
--- `//server/share/...` prefix is never collapsed to a single slash.
---
--- Deliberately does **not** route through
--- `lib.nvim.cross.fs.separators.collapse_dots`: that module has a confirmed
--- gap where it does not special-case a UNC prefix (see its README) and
--- would corrupt one. This module keeps its own guarded collapse instead.

local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
local drive_upper = require("lib.nvim.cross.fs.separators.drive_upper")

local uv = vim.uv or vim.loop

---@param p string
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
    out = uv.fs_realpath(p) or p
  end

  out = unify_slashes(out)
  out = drive_upper(out)

  -- Collapse duplicate slashes, but keep a UNC prefix ("//server/share") intact.
  if not out:match("^//") then
    out = out:gsub("//+", "/")
  end

  return out
end
