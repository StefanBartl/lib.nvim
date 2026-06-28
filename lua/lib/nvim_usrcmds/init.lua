---@module 'lib.nvim_usrcmds'
-- Utility user commands that don't belong in a more specific plugin.
-- Each command is opt-in and can be toggled independently in setup().

require("lib.nvim_usrcmds.@types")

local M = {}

---@type Lib.NvimUsrCmds.Options
local defaults = {
  helptags           = true,
  cwd_here           = true,
  powershell_profile = vim.fn.has("win32") == 1,
}

local function register_helptags()
  vim.api.nvim_create_autocmd("User", {
    pattern  = "LazyDone",
    once     = true,
    callback = function() vim.cmd("helptags ALL") end,
    desc     = "[lib.nvim_usrcmds] regenerate helptags after lazy.nvim finishes loading",
  })
end

-- FIX: neotree/nvimtree/netrw does not auto-refresh after lcd — trigger a
-- manual refresh in the file-tree plugin if needed.
local function register_cwd_here()
  vim.api.nvim_create_user_command("CwdHere", function()
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname == "" then return end
    local dir = vim.fn.fnamemodify(bufname, ":p:h")
    vim.cmd("lcd " .. vim.fn.fnameescape(dir))
  end, { desc = "Set local cwd to the directory of the current buffer" })
end

local function register_powershell_profile()
  vim.api.nvim_create_user_command("PowershellProfile", function()
    if vim.fn.executable("powershell") ~= 1 then
      vim.notify("[lib.nvim_usrcmds] PowershellProfile: powershell not available on this system", vim.log.levels.ERROR)
      return
    end
    local res = vim.system(
      { "powershell", "-NoProfile", "-Command", "[Console]::Write($PROFILE)" },
      { text = true }
    ):wait()
    local path = res.code == 0 and res.stdout or nil
    if path and path ~= "" then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    else
      vim.notify("[lib.nvim_usrcmds] PowershellProfile: could not resolve profile path", vim.log.levels.ERROR)
    end
  end, { desc = "Open the active PowerShell profile in Neovim" })
end

---@param opts Lib.NvimUsrCmds.Options|nil
function M.setup(opts)
  local o = vim.tbl_extend("force", defaults, opts or {})
  if o.helptags           then register_helptags()           end
  if o.cwd_here           then register_cwd_here()           end
  if o.powershell_profile then register_powershell_profile() end
end

return M
