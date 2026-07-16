---@module 'lib.nvim.fs.trash'
--- Cross-platform "send to trash/recycle bin" (not a permanent delete).
---
--- Dispatches to the OS-native trash mechanism: `Microsoft.VisualBasic
--- .FileIO.FileSystem` via PowerShell on native Windows, Finder via
--- `osascript` on macOS, and `gio trash` / `trash-put` on Linux (and WSL,
--- when a Linux desktop trash implementation is available). When none of
--- those are available on Linux, falls back to moving the entry into the
--- XDG trash directory directly — see the `M.trash`/`M.trash_blocking` docs
--- below for the limitation that entails.
---
---```lua
--- local trash = require("lib.nvim.fs.trash")
---
--- trash.trash("/tmp/some_file.txt", function(ok, err)
---   if not ok then vim.notify(err, vim.log.levels.ERROR) end
--- end)
---
--- local ok, err = trash.trash_blocking("/tmp/some_dir")
---```

require("lib.nvim.fs.trash.@types")

local run = require("lib.nvim.cross.run")
local is_windows = require("lib.nvim.cross.platform.is_windows")
local is_macos = require("lib.nvim.cross.platform.is_macos")
local is_linux = require("lib.nvim.cross.platform.is_linux")
local is_wsl = require("lib.nvim.cross.platform.is_wsl")

local uv = vim.uv or vim.loop

local M = {}

---Escape `str` for embedding in a single-quoted POSIX shell argument.
---@param str string
---@return string
local function sh_quote(str)
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

---Escape `str` for embedding in a single-quoted PowerShell string literal.
---@param str string
---@return string
local function ps_quote(str)
  return str:gsub("'", "''")
end

---Escape `str` for embedding in a double-quoted AppleScript string literal.
---@param str string
---@return string
local function osa_quote(str)
  return (str:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

---@param path string
---@return string
local function windows_cmd(path)
  local is_dir = vim.fn.isdirectory(path) == 1
  local method = is_dir and "DeleteDirectory" or "DeleteFile"
  return "Add-Type -AssemblyName Microsoft.VisualBasic; "
    .. "[Microsoft.VisualBasic.FileIO.FileSystem]::"
    .. method
    .. "('"
    .. ps_quote(path)
    .. "','OnlyErrorDialogs','SendToRecycleBin')"
end

---@param path string
---@return string
local function macos_cmd(path)
  return "osascript -e 'tell application \"Finder\" to delete POSIX file \""
    .. osa_quote(path)
    .. "\"'"
end

---Directory that holds trashed files for the XDG fallback.
---@return string
local function xdg_trash_files_dir()
  local xdg = vim.env.XDG_DATA_HOME
  local base = (xdg ~= nil and xdg ~= "") and xdg or (vim.env.HOME .. "/.local/share")
  return base .. "/Trash/files"
end

---Fallback: move `path` into the XDG trash directory via `fs_rename`.
---NOTE: this does not write the accompanying `.trashinfo` metadata that real
---trash implementations use, so "restore from trash" UIs may not show the
---original path — an accepted limitation of this fallback path only.
---@param path string
---@return boolean ok
---@return string|nil err
local function xdg_fallback_blocking(path)
  local trash_dir = xdg_trash_files_dir()
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, trash_dir, "p")
  if not ok_mkdir then
    return false, "mkdir failed: " .. tostring(err_mkdir)
  end

  local dest = trash_dir .. "/" .. vim.fn.fnamemodify(path, ":t")
  local ok, err = uv.fs_rename(path, dest)
  if not ok then
    return false, "fs_rename failed: " .. tostring(err)
  end
  return true, nil
end

---Fallback: move `path` into the XDG trash directory, asynchronously.
---@param path string
---@param cb fun(ok: boolean, err: string|nil)
local function xdg_fallback_async(path, cb)
  local trash_dir = xdg_trash_files_dir()
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, trash_dir, "p")
  if not ok_mkdir then
    vim.schedule(function()
      cb(false, "mkdir failed: " .. tostring(err_mkdir))
    end)
    return
  end

  local dest = trash_dir .. "/" .. vim.fn.fnamemodify(path, ":t")
  uv.fs_rename(path, dest, function(err)
    vim.schedule(function()
      cb(err == nil, err)
    end)
  end)
end

---Build the Linux trash command to run, or `nil` if only the fallback applies.
---@param path string
---@return string|nil cmd
local function linux_cmd(path)
  if vim.fn.executable("gio") == 1 then
    return "gio trash -- " .. sh_quote(path)
  end
  if vim.fn.executable("trash-put") == 1 then
    return "trash-put -- " .. sh_quote(path)
  end
  return nil
end

---Send `path` to the OS trash/recycle bin, asynchronously.
---@param path string
---@param cb fun(ok: boolean, err: string|nil)
function M.trash(path, cb)
  if is_windows() and not is_wsl() then
    run.run(windows_cmd(path), function(ok, res)
      cb(ok, ok and nil or (res.stderr ~= "" and res.stderr or "trash failed"))
    end)
    return
  end

  if is_macos() then
    run.run(macos_cmd(path), function(ok, res)
      cb(ok, ok and nil or (res.stderr ~= "" and res.stderr or "trash failed"))
    end)
    return
  end

  if is_linux() or is_wsl() then
    local cmd = linux_cmd(path)
    if cmd then
      run.run(cmd, function(ok, res)
        cb(ok, ok and nil or (res.stderr ~= "" and res.stderr or "trash failed"))
      end)
      return
    end
    xdg_fallback_async(path, cb)
    return
  end

  cb(false, "unsupported platform")
end

---Send `path` to the OS trash/recycle bin, synchronously.
---@param path string
---@return boolean ok
---@return string|nil err
function M.trash_blocking(path)
  if is_windows() and not is_wsl() then
    local res = run.run_blocking(windows_cmd(path))
    if res.code == 0 then
      return true, nil
    end
    return false, (res.stderr ~= "" and res.stderr) or "trash failed"
  end

  if is_macos() then
    local res = run.run_blocking(macos_cmd(path))
    if res.code == 0 then
      return true, nil
    end
    return false, (res.stderr ~= "" and res.stderr) or "trash failed"
  end

  if is_linux() or is_wsl() then
    local cmd = linux_cmd(path)
    if cmd then
      local res = run.run_blocking(cmd)
      if res.code == 0 then
        return true, nil
      end
      return false, (res.stderr ~= "" and res.stderr) or "trash failed"
    end
    return xdg_fallback_blocking(path)
  end

  return false, "unsupported platform"
end

---@type Lib.Fs.Trash
return M
