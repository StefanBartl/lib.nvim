---@module 'lib.nvim.fs.open.url.system_opener'
--- Open a path/URL with the OS default handler — the shared per-OS dispatch
--- every plugin that shells out to `open`/`xdg-open`/`start` was reimplementing
--- independently (see the `lib_NEW_MODULES.md`/`replace_moduls.md` survey).
---
--- Dispatch order:
---   1. `vim.ui.open` (Neovim 0.10+) unless `cfg.prefer_ui_open == false` or
---      `cfg.on_exit` was passed. This is the shell-independent, upstream-
---      maintained path and should win whenever it exists.
---   2. A per-OS **argv list** — never a shell string. The list form matters:
---      the string form goes through `&shell` + `shellescape`, which quotes
---      paths containing spaces incorrectly under `shell=pwsh` on Windows.
---   3. WSL gets `wslview` (which hands the URL to the Windows host) before
---      falling back to `xdg-open`, since a WSL distro usually has no desktop
---      for `xdg-open` to talk to.
---
--- `cfg` is entirely optional. Windows support is enabled by default (via
--- `cmd.exe /c start`); pass `cfg.enable_windows_opener = false` to opt back
--- out. `cfg.open_cmd_mac`/`open_cmd_unix`/`open_cmd_wsl` override the
--- respective command.

require("lib.nvim.fs.open.url.system_opener.@types")

local M = {}

---Resolve the argv list for the current platform.
---@param url string
---@param cfg AutoCmds.General.MD.GotoFile.Cfg
---@return string[]|nil
local function resolve_opener(url, cfg)
  if vim.fn.has("macunix") == 1 then
    return cfg.open_cmd_mac or { "open", url }
  end

  if vim.fn.has("unix") == 1 then
    -- WSL: `xdg-open` typically has no desktop to hand the URL to, while
    -- `wslview` (from wslu) forwards it to the Windows host's default handler.
    if require("lib.nvim.cross.platform.is_wsl")() and vim.fn.executable("wslview") == 1 then
      return cfg.open_cmd_wsl or { "wslview", url }
    end
    return cfg.open_cmd_unix or { "xdg-open", url }
  end

  if cfg.enable_windows_opener ~= false and vim.fn.has("win32") == 1 then
    -- The empty string is `start`'s window-title argument: without it, a
    -- quoted first argument is consumed as the title instead of the target.
    return { "cmd.exe", "/c", "start", "", url }
  end

  return nil
end

--- In-place "open URL" via system opener.
---
--- The return value reports whether an opener was *dispatched*, not whether
--- it succeeded — the default path is detached and fire-and-forget. Pass
--- `cfg.on_exit` to observe the actual exit code; that keeps the job attached
--- and skips `vim.ui.open` (whose handle would have to be waited on
--- synchronously).
---@param url string
---@param cfg? AutoCmds.General.MD.GotoFile.Cfg
---@return boolean opened
function M.open(url, cfg)
  cfg = cfg or {}

  if cfg.prefer_ui_open ~= false and not cfg.on_exit and vim.ui and vim.ui.open then
    local ok, handle = pcall(vim.ui.open, url)
    if ok and handle then
      return true
    end
    -- Fall through to the argv dispatch: either `vim.ui.open` errored, or it
    -- reported that it found no usable opener on this system.
  end

  local opener = resolve_opener(url, cfg)
  if not opener then
    return false
  end

  -- Replace placeholder if custom arrays were provided like {"open", "<url>"}.
  for i, v in ipairs(opener) do
    if v == "<url>" then
      opener[i] = url
    end
  end

  if cfg.on_exit then
    -- Exit-code reporting requires keeping the job attached.
    local jid = vim.fn.jobstart(opener, {
      on_exit = function(_, code)
        cfg.on_exit(code)
      end,
    })
    if jid <= 0 then
      return false
    end
    return true
  end

  vim.fn.jobstart(opener, { detach = true })
  return true
end

--- Quick predicate: looks like a web/URI target.
---@param s string
---@return boolean
function M.is_like(s)
  if s:match("^https?://") or s:match("^file://") then
    return true
  end
  if s:match("^www%.") then
    return true
  end
  if s:match("^[A-Za-z0-9%-_]+%.[A-Za-z]+") then
    return true
  end
  return false
end

--- Deprecated misspelling of `is_like`, kept as an alias so existing call
--- sites keep working. Prefer `M.is_like`.
---@param s string
---@return boolean
M.is_ike = M.is_like

return M
