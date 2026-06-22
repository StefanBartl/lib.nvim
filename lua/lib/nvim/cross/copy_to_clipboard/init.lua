---@module 'lib.nvim.cross.copy_to_clipboard'
-- Cross plattform clipboard function

---FIX: Optmize

--- Copy text to system clipboard using platform-appropriate backend.
---@param text string
---@return boolean
return function (text)
local lib = require("lib")
  -- 1) Try Neovim register (+)
  local ok = pcall(vim.fn.setreg, "+", text)
  if ok then
    return true
  end

  -- 2) macOS pbcopy
  if lib.is_macos() then
    local res = lib.run_blocking("pbcopy")
    if res.code == 0 then
      return true
    end
  end

  -- 3) Linux: xclip / wl-copy (best effort)
  if lib.is_linux() and not lib.is_wsl() then
    local r1 = lib.run_blocking("xclip -selection clipboard " .. text)
    if r1.code == 0 then
      return true
    end
    local r2 = lib.run_blocking("wl-copy " .. text)
    if r2.code == 0 then
      return true
    end
  end

  -- 4) Windows native PowerShell
  if lib.is_windows() and not lib.is_wsl() then
    local cmd = "$input | Set-Clipboard"
    local sh = lib.shell()
    local obj = vim.system and vim.system({ sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd }, { stdin = text }):wait()
    return (obj and obj.code == 0)
  end

  -- 5) WSL → clip.exe (Windows clipboard)
  if lib.is_wsl() then
    local obj = vim.system and vim.system({ "clip.exe" }, { stdin = text }):wait()
    return (obj and obj.code == 0)
  end

  return false
end
