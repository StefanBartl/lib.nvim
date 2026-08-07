---@module 'lib.nvim.cross.reveal_in_fm'
--- Show a path in the system file manager — "reveal in Explorer/Finder/…",
--- as opposed to `lib.nvim.cross.open_default`, which hands the path to the
--- application registered for its extension.
---
--- A directory target is always navigated INTO. A file target is either
--- selected inside its parent directory (`reveal = true`, the default) or,
--- with `reveal = false`, its parent directory is opened without selecting
--- anything — the second form matters on Linux, where selecting requires a
--- file manager that supports it (see below).
---
--- Platform dispatch:
---   Windows → explorer.exe /select,<path>   (file, reveal)
---             explorer.exe <dir>            (directory, or reveal = false)
---   WSL     → same, after converting the path via `wslpath -w`
---   macOS   → open -R <file> / open <dir>
---   Linux   → the first available manager on PATH. Revealing a FILE only
---             uses a manager known to select it (nautilus, nemo, dolphin,
---             thunar, caja, pcmanfm); `xdg-open` is never given a file,
---             because it would launch the file's default application
---             instead of a file manager. With no select-capable manager
---             present, the parent directory is opened instead.
---
--- Windows paths are converted to backslashes before dispatch: explorer.exe
--- does not reliably accept forward slashes, and `/select,C:/x/y` in
--- particular silently opens the wrong folder rather than failing.
---
--- Consolidates two independent copies of this dispatch: open.nvim's
--- `handlers/filemanager.lua` and filetree.nvim's
--- `features/system/open_in_fm`.

local run = require("lib.nvim.cross.run")
local expand_path = require("lib.nvim.cross.fs.expand_path")

---Linux file managers, in preference order, with whether the manager can
---select (highlight) a file when given the file's own path.
---`xdg-open` leads the list for directories precisely because it honours the
---user's configured manager, but it is skipped whenever a file must be
---selected.
---@type { cmd: string, args: string[]?, select: boolean }[]
local LINUX_MANAGERS = {
  { cmd = "xdg-open", select = false },
  { cmd = "nautilus", select = true },
  { cmd = "nemo", select = true },
  { cmd = "dolphin", args = { "--select" }, select = true },
  { cmd = "thunar", select = true },
  { cmd = "caja", select = true },
  { cmd = "pcmanfm", select = false },
}

---@internal
---@param path string
---@return boolean
local function is_file(path)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

---@internal
---@param path string
---@return string
local function parent_of(path)
  return vim.fn.fnamemodify(path, ":h")
end

---@internal
---@param path string
---@return string
local function to_win_sep(path)
  return (path:gsub("/", "\\"))
end

---@internal
---Build the argv for a Linux file manager, honouring `want_select`.
---Returns nil when no manager is on PATH at all.
---@param path string        Absolute path to the target.
---@param file boolean       Whether the target is a regular file.
---@param want_select boolean
---@return string[]|nil argv
local function linux_argv(path, file, want_select)
  local fallback ---@type string[]|nil

  for _, mgr in ipairs(LINUX_MANAGERS) do
    if vim.fn.executable(mgr.cmd) == 1 then
      if file and want_select then
        if mgr.select then
          local argv = { mgr.cmd }
          for _, a in ipairs(mgr.args or {}) do
            argv[#argv + 1] = a
          end
          argv[#argv + 1] = path
          return argv
        end
        -- Not select-capable: remember it as the "open the parent instead"
        -- fallback, but keep looking for one that can select.
        fallback = fallback or { mgr.cmd, parent_of(path) }
      else
        return { mgr.cmd, file and parent_of(path) or path }
      end
    end
  end

  return fallback
end

---Reveal `target` in the system file manager.
---@param target string                          Path to a file or directory (`~`/env vars are expanded).
---@param opts Lib.Cross.RevealInFm.Opts|nil
---@return boolean ok
---@return string|nil err
return function(target, opts)
  opts = opts or {}

  if type(target) ~= "string" or target == "" then
    return false, "empty target"
  end

  local path = expand_path(target)
  if path == "" then
    return false, "cannot resolve path: " .. target
  end

  local reveal = opts.reveal ~= false
  local file = is_file(path)

  local is_windows = require("lib.nvim.cross.platform.is_windows")()
  local is_wsl = require("lib.nvim.cross.platform.is_wsl")()
  local is_macos = require("lib.nvim.cross.platform.is_macos")()

  -- An explicit launcher override skips platform dispatch entirely: the user
  -- named the program, so the only sane thing to pass it is the path. A file
  -- still resolves to its parent directory when `reveal = false`, matching
  -- what the built-in branches do.
  if opts.command and opts.command ~= "" then
    local argv = type(opts.command) == "table" and vim.deepcopy(opts.command) or { opts.command }
    local arg = (file and not reveal) and parent_of(path) or path
    -- The override may well be explorer.exe itself, which is the one launcher
    -- that insists on backslashes.
    argv[#argv + 1] = (is_windows and not is_wsl) and to_win_sep(arg) or arg
    return run.run_detached(argv)
  end

  local cmd ---@type string[]|nil

  if is_windows and not is_wsl then
    local win = to_win_sep(path)
    if file and reveal then
      -- `/select,<path>` is one argument, comma included — a space after the
      -- comma makes explorer.exe ignore the path and open Documents.
      cmd = { "explorer.exe", "/select," .. win }
    else
      cmd = { "explorer.exe", file and to_win_sep(parent_of(path)) or win }
    end
  elseif is_wsl then
    local unix_target = (file and not reveal) and parent_of(path) or path
    local win = require("lib.nvim.cross.fs.wslpath").to_win(unix_target)
    if not win then
      -- A Linux-side path with no Windows-side equivalent: fall back to the
      -- Linux managers rather than failing outright.
      cmd = linux_argv(path, file, reveal)
      if not cmd then
        return false, "wslpath conversion failed for: " .. unix_target
      end
    elseif file and reveal then
      cmd = { "explorer.exe", "/select," .. win }
    else
      cmd = { "explorer.exe", win }
    end
  elseif is_macos then
    if file and reveal then
      cmd = { "open", "-R", path }
    else
      cmd = { "open", file and parent_of(path) or path }
    end
  else
    cmd = linux_argv(path, file, reveal)
    if not cmd then
      return false, "no file manager found on PATH"
    end
  end

  return run.run_detached(cmd)
end
