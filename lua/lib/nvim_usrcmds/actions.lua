---@module 'lib.nvim_usrcmds.actions'
---@brief The command bodies, shared by both surfaces.
---@description
--- The flat commands (`:CwdHere`, `:PowershellProfile`) and the `:Lib` verb's
--- routes dispatch to the exact same functions, so the two surfaces cannot
--- drift into doing different things under the same name.

local notify = require("lib.nvim.notify").create("[lib.nvim_usrcmds]")

local M = {}

--- CDX: neo-tree/nvim-tree/netrw do not auto-refresh after `lcd`; a manual
--- CDX: refresh of the active file-tree plugin is still to be implemented here.

---Set the local (window) cwd to the directory of the current buffer.
---@return nil
function M.cwd_here()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    return
  end
  local dir = vim.fn.fnamemodify(bufname, ":p:h")
  vim.cmd("lcd " .. vim.fn.fnameescape(dir))
end

---Open the active PowerShell profile (`$PROFILE`) in Neovim.
---@return nil
function M.powershell_profile()
  if vim.fn.executable("powershell") ~= 1 then
    notify.error("PowershellProfile: powershell not available on this system")
    return
  end
  local res = vim
    .system({ "powershell", "-NoProfile", "-Command", "[Console]::Write($PROFILE)" }, { text = true })
    :wait()
  local path = res.code == 0 and res.stdout or nil
  if path and path ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    notify.error("PowershellProfile: could not resolve profile path")
  end
end

---Regenerate helptags for every installed plugin.
---@return nil
function M.helptags()
  vim.cmd("helptags ALL")
end

return M
