---@module 'lib.nvim.cross.open_default'
--- Open a path or URL with the system's default application — the
--- cross-platform equivalent of double-clicking it in a file manager
--- (extension/URL-scheme decides the app: PDF → PDF viewer, .docx → Word,
--- https:// → default browser).
---
--- Platform dispatch:
---   Windows → cmd.exe /C start "" <target>
---   WSL     → converts path to a Windows path via `wslpath`, then same as
---             Windows; a URL skips straight to cmd.exe's start (no path to
---             convert); falls back to `xdg-open` for a Linux-side file with
---             no Windows-side equivalent.
---   macOS   → open <target>
---   Linux   → xdg-open <target>
---
--- Upstreamed from open.nvim's `handlers/default.lua` (the most complete of
--- three independent copies found across the author's plugins —
--- markdown.nvim's own version, for one, has no WSL handling at all). Spawns
--- detached via `lib.nvim.cross.run.run_detached`, matching how that helper
--- was itself upstreamed from open.nvim previously.

local run = require("lib.nvim.cross.run")
local expand_path = require("lib.nvim.cross.fs.expand_path")

---@param text string
---@return boolean
local function looks_like_url(text)
  return text:match("^https?://") ~= nil
    or text:match("^ftp://") ~= nil
    or text:match("^www%.") ~= nil
end

---@param unix_path string
---@return string|nil
local function wsl_to_win_path(unix_path)
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured({ "wslpath", "-w", unix_path })
  if not ok then
    return nil
  end
  out = out:gsub("\n", "")
  return (out ~= "" and out) or nil
end

---Open `target` (a filesystem path or URL) with the system default handler.
---@param target string
---@return boolean ok
---@return string|nil err
return function(target)
  if type(target) ~= "string" or target == "" then
    return false, "empty target"
  end

  local is_windows = require("lib.nvim.cross.platform.is_windows")()
  local is_wsl = require("lib.nvim.cross.platform.is_wsl")()
  local is_macos = require("lib.nvim.cross.platform.is_macos")()

  local cmd

  if is_windows and not is_wsl then
    cmd = { "cmd.exe", "/C", "start", '""', expand_path(target) }
  elseif is_wsl then
    if looks_like_url(target) then
      cmd = { "cmd.exe", "/C", "start", '""', target }
    else
      local win_path = wsl_to_win_path(expand_path(target))
      if win_path then
        cmd = { "cmd.exe", "/C", "start", '""', win_path }
      elseif vim.fn.executable("xdg-open") == 1 then
        cmd = { "xdg-open", target }
      else
        return false, "cannot determine how to open: " .. target
      end
    end
  elseif is_macos then
    cmd = { "open", expand_path(target) }
  else
    if vim.fn.executable("xdg-open") ~= 1 then
      return false, "xdg-open not found — install xdg-utils"
    end
    cmd = { "xdg-open", expand_path(target) }
  end

  return run.run_detached(cmd)
end
