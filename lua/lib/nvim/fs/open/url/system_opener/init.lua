---@module 'lib.nvim.fs.open.url.system_opener'
--- Open a path/URL with the OS default handler — the shared per-OS dispatch
--- every plugin that shells out to `open`/`xdg-open`/`start` was reimplementing
--- independently (see the `lib_NEW_MODULES.md`/`replace_moduls.md` survey).
---
--- `cfg` is entirely optional. Windows support is enabled by default (via
--- `cmd.exe /c start`); pass `cfg.enable_windows_opener = false` to opt back
--- out. `cfg.open_cmd_mac`/`open_cmd_unix` override the mac/Linux command.

local M = {}

--- In-place "open URL" via system opener.
---@param url string
---@param cfg? AutoCmds.General.MD.GotoFile.Cfg
---@return boolean opened
function M.open(url, cfg)
  cfg = cfg or {}
  local opener ---@type string[]|nil

  if vim.fn.has("macunix") == 1 then
    opener = cfg.open_cmd_mac or { "open", url }
  elseif vim.fn.has("unix") == 1 then
    opener = cfg.open_cmd_unix or { "xdg-open", url }
  elseif cfg.enable_windows_opener ~= false and vim.fn.has("win32") == 1 then
    opener = { "cmd.exe", "/c", "start", "", url }
  end

  if not opener then
    return false
  end
  -- Replace placeholder if custom arrays were provided like {"open", "<url>"}.
  for i, v in ipairs(opener) do
    if v == "<url>" then
      opener[i] = url
    end
  end
  vim.fn.jobstart(opener, { detach = true })
  return true
end

--- Quick predicate: looks like a web/URI target.
---@param s string
---@return boolean
function M.is_ike(s)
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

return M
