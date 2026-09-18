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

---@internal
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

---@internal
--- Set the `+` register and verify the write actually took, rather than
--- trusting `pcall`'s success as a proxy for it.
---
--- `vim.fn.setreg("+", text)` does not raise when there is no clipboard
--- provider -- it just silently does nothing, after printing "clipboard:
--- No provider" to `:messages`. So `pcall(vim.fn.setreg, ...)` was always
--- `true` on a machine with no provider AND no external tool, and this
--- function reported success while nothing was actually on the clipboard.
--- Every caller across this fleet trusted that return value to tell a user
--- "copied" -- that was the actual bug, not a CI quirk: any Linux session
--- with no `xclip`/`xsel`/`wl-copy` and no `g:clipboard` configured hit it.
---@param text string
---@return boolean
local function try_native_register(text)
  local ok = pcall(vim.fn.setreg, "+", text)
  if not ok then
    return false
  end
  local ok2, got = pcall(vim.fn.getreg, "+")
  return ok2 and got == text
end

--- Copy text to system clipboard using platform-appropriate backend.
---@param text string
---@return boolean
return function(text)
  local lib = require("lib")

  -- 1) Try Neovim register (+)
  if try_native_register(text) then
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
    if vim.system then
      local ok2, obj = pcall(function()
        -- `cross.run.argv` keeps every shell argument, `-Command` included.
        return vim.system(require("lib.nvim.cross.run").argv(cmd), { stdin = text }):wait()
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
