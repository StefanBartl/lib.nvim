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
---   Windows → win_reveal.ps1, which runs explorer.exe /select,<path> (file,
---             reveal) or explorer.exe <dir> and then RAISES the resulting
---             window (see below)
---   WSL     → the same script via powershell.exe, after converting both the
---             target and the script path with `wslpath -w`
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
--- Why Windows goes through a PowerShell script instead of spawning
--- explorer.exe directly: spawning it directly DOES create the window, but
--- the window never comes to the front, which is the only part the user can
--- observe. Windows grants SetForegroundWindow only to the process that owns
--- the foreground window; with Neovim in a terminal that process is the
--- terminal host, not nvim.exe, so both nvim and the Explorer it spawns are
--- denied and the new window is created behind everything. Under a GUI
--- Neovim (Neovide, nvim-qt) nvim.exe *is* the foreground process and the
--- identical code appeared to work — hence the long history of this bug
--- being "fixed", then regressing with no reproducible pattern. win_reveal.ps1
--- locates the window Explorer opened and raises it via AttachThreadInput;
--- see its header for the mechanism.
---
--- If PowerShell or the script is unavailable, the direct explorer.exe spawn
--- is still used: a window that opens behind other windows beats no window.
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
---Absolute path of win_reveal.ps1, which ships next to this file.
---Resolved from this chunk's own source rather than `nvim_get_runtime_file`
---so it also works when lib.nvim is loaded from outside 'runtimepath'.
---@return string|nil
local function win_script()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) ~= "@" then
    return nil
  end
  local path = vim.fn.fnamemodify(source:sub(2), ":h") .. "/win_reveal.ps1"
  local uv = vim.uv or vim.loop
  return uv.fs_stat(path) and path or nil
end

---@internal
---PowerShell executable for the raise step. Windows PowerShell is preferred
---over pwsh purely because it is guaranteed to be present; either works.
---@param wsl boolean
---@return string|nil
local function powershell(wsl)
  for _, exe in ipairs(wsl and { "powershell.exe", "pwsh.exe" } or { "powershell", "pwsh" }) do
    if vim.fn.executable(exe) == 1 then
      return exe
    end
  end
  return nil
end

---@internal
---Spawn the PowerShell helper.
---
---Deliberately NOT `run.run_detached`: on Windows that uses
---`jobstart(..., { detach = true })`, and libuv's DETACHED_PROCESS leaves the
---child with no standard handles, whereupon powershell.exe exits before
---running a single statement — verified with a detached one-liner whose only
---job was to write a marker file, which never appeared. explorer.exe survives
---that treatment because it is a GUI process; PowerShell does not. This is
---exactly why the first version of this fix silently did nothing.
---
---An ordinary piped spawn is the right shape anyway: the helper lives a
---second or two, nothing ever waits on it, and if Neovim quits in that window
---there is no window left to raise.
---@param argv string[]
---@return boolean ok
---@return string|nil err
local function spawn_helper(argv)
  if vim.system then
    local ok, err = pcall(vim.system, argv, {})
    if not ok then
      return false, tostring(err)
    end
    return true, nil
  end

  -- Neovim < 0.10. The empty handlers are load-bearing: they are what makes
  -- jobstart set up the pipes the child needs.
  local jid = vim.fn.jobstart(argv, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function() end,
    on_stderr = function() end,
  })
  if jid <= 0 then
    return false, "jobstart failed"
  end
  return true, nil
end

---@internal
---Build the argv that reveals `win_path` through win_reveal.ps1, or nil when
---PowerShell or the script is missing and the caller must fall back to a
---bare explorer.exe spawn.
---@param win_path string   Absolute Windows path, backslash-separated.
---@param select boolean    Highlight a file inside its parent directory.
---@param reuse boolean     Navigate an existing Explorer window instead.
---@param wsl boolean
---@return string[]|nil
local function win_reveal_argv(win_path, select, reuse, wsl)
  local exe = powershell(wsl)
  local script = win_script()
  if not exe or not script then
    return nil
  end

  local script_arg ---@type string|nil
  if wsl then
    -- powershell.exe is a Windows process: it cannot read the /mnt/... form.
    script_arg = require("lib.nvim.cross.fs.wslpath").to_win(script)
    if not script_arg then
      return nil
    end
  else
    script_arg = to_win_sep(script)
  end

  local argv = {
    exe,
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    script_arg,
    "-Path",
    win_path,
  }
  if select then
    argv[#argv + 1] = "-Select"
  end
  if reuse then
    argv[#argv + 1] = "-Reuse"
  end
  return argv
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
  -- what the built-in branches do. The Windows raise is skipped too — it
  -- looks the window up as an Explorer folder window, which an arbitrary
  -- third-party manager is not.
  local command = opts.command
  if command and command ~= "" then
    -- Through a local, so the `type(...)` test actually narrows it.
    local argv = type(command) == "table" and vim.deepcopy(command) or { command }
    local arg = (file and not reveal) and parent_of(path) or path
    -- The override may well be explorer.exe itself, which is the one launcher
    -- that insists on backslashes.
    argv[#argv + 1] = (is_windows and not is_wsl) and to_win_sep(arg) or arg
    return run.run_detached(argv)
  end

  local cmd ---@type string[]|nil
  local via_helper = false ---@type boolean

  local reuse = opts.reuse == true

  if is_windows and not is_wsl then
    local select = file and reveal
    local win = to_win_sep(select and path or (file and parent_of(path) or path))
    cmd = win_reveal_argv(win, select, reuse, false)
    via_helper = cmd ~= nil
    if not cmd then
      -- No PowerShell: the window will open behind other windows, but it
      -- opens. `/select,<path>` is one argument, comma included — a space
      -- after the comma makes explorer.exe ignore the path and open Documents.
      cmd = { "explorer.exe", select and ("/select," .. win) or win }
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
    else
      local select = file and reveal
      cmd = win_reveal_argv(win, select, reuse, true)
      via_helper = cmd ~= nil
      if not cmd then
        cmd = { "explorer.exe", select and ("/select," .. win) or win }
      end
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

  if via_helper then
    return spawn_helper(cmd)
  end
  return run.run_detached(cmd)
end
