---@meta
---@module 'lib.nvim_usrcmds.@types'

---@class Lib.NvimUsrCmds.Options
---@field helptags?           boolean  Regenerate helptags for all plugins after LazyDone (default: true)
---@field cwd_here?           boolean  Register :CwdHere — set local cwd to current buffer's directory (default: true)
---@field powershell_profile? boolean  Register :PowershellProfile — open the active PS profile in Neovim (default: true on Windows, false elsewhere)
---@field lib_verb?           boolean  Register the unified :Lib verb (cwd-here | ps-profile | helptags) via composer, with completion (default: true)

return {}
