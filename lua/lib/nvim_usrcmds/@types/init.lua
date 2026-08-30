---@meta
---@module 'lib.nvim_usrcmds.@types'

---@class Lib.NvimUsrCmds.Options
---@field helptags?           boolean  Regenerate helptags for all plugins after lazy.nvim installs/updates/syncs (NOT on every start -- see register_helptags) (default: true)
---@field cwd_here?           boolean  Register :CwdHere — set local cwd to current buffer's directory (default: true)
---@field powershell_profile? boolean  Register :PowershellProfile — open the active PS profile in Neovim (default: true on Windows, false elsewhere)
---@field lib_verb?           boolean  Register the unified :Lib verb (cwd-here | ps-profile | helptags) via composer, with completion (default: true)
---@field deps?               boolean  Add `:Lib deps show|install <plugin>` — inspect/install another plugin's declared external tools (default: true; requires lib_verb)
---@field hover?              boolean  Add `:Lib hover toggle|on|off` — switch the path/link hover off for the session and back on (default: true; requires lib_verb)

return {}
