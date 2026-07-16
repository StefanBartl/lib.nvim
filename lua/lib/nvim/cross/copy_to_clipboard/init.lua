---@module 'lib.nvim.cross.copy_to_clipboard'
--- Cross-platform clipboard write. Tries the Neovim `+` register first, then
--- an OS-appropriate external tool as a fallback, piping `text` via stdin
--- (never interpolated into a shell command string — string interpolation
--- into `xclip`/`wl-copy` invocations was a real command-injection bug fixed
--- here: a `text` value containing shell metacharacters could execute
--- arbitrary commands).
---
--- Linux picks `wl-copy` under Wayland and `xclip`/`xsel` under X11 (checked
--- via `$WAYLAND_DISPLAY`/`$DISPLAY`), falling back to trying whichever
--- tool is actually on PATH if the display-server guess doesn't pan out.

local core = require("lib.nvim.core")

---@param argv string[]
---@param text string
---@return boolean
local function run_with_stdin(argv, text)
  if not vim.system then
    return false
  end
  if not core.has_exec(argv[1]) then
    return false
  end
  local ok, obj = pcall(function()
    return vim.system(argv, { stdin = text }):wait()
  end)
  return ok and obj ~= nil and obj.code == 0
end

--- Copy text to system clipboard using platform-appropriate backend.
---@param text string
---@return boolean
return function(text)
  local lib = require("lib")

  -- 1) Try Neovim register (+)
  local ok = pcall(vim.fn.setreg, "+", text)
  if ok then
    return true
  end

  -- 2) macOS
  if lib.is_macos() then
    if run_with_stdin({ "pbcopy" }, text) then
      return true
    end
  end

  -- 3) Linux (not WSL): prefer the tool matching the detected display server,
  -- then fall back to trying every known candidate regardless.
  if lib.is_linux() and not lib.is_wsl() then
    local is_wayland = (vim.env.WAYLAND_DISPLAY or "") ~= ""
    local is_x11 = (vim.env.DISPLAY or "") ~= ""

    if is_wayland and run_with_stdin({ "wl-copy" }, text) then
      return true
    end
    if is_x11 then
      if run_with_stdin({ "xclip", "-selection", "clipboard" }, text) then
        return true
      end
      if run_with_stdin({ "xsel", "--clipboard", "--input" }, text) then
        return true
      end
    end
    if run_with_stdin({ "wl-copy" }, text) then
      return true
    end
    if run_with_stdin({ "xclip", "-selection", "clipboard" }, text) then
      return true
    end
    if run_with_stdin({ "xsel", "--clipboard", "--input" }, text) then
      return true
    end
  end

  -- 4) Windows native PowerShell
  if lib.is_windows() and not lib.is_wsl() then
    local cmd = "$input | Set-Clipboard"
    local sh = lib.shell()
    if vim.system then
      local ok2, obj = pcall(function()
        return vim.system({ sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd }, { stdin = text }):wait()
      end)
      if ok2 and obj and obj.code == 0 then
        return true
      end
    end
  end

  -- 5) WSL → clip.exe (Windows clipboard), with an absolute-path fallback
  -- for the case where clip.exe isn't resolved via PATH.
  if lib.is_wsl() then
    if run_with_stdin({ "clip.exe" }, text) then
      return true
    end
    local clip_abs = "/mnt/c/Windows/System32/clip.exe"
    if vim.fn.filereadable(clip_abs) == 1 and run_with_stdin({ clip_abs }, text) then
      return true
    end
  end

  return false
end
