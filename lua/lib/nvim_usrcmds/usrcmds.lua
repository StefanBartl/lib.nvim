---@module 'lib.nvim_usrcmds.usrcmds'
---@brief The user commands this namespace installs.
---@description
--- Two surfaces over the same actions, deliberately:
---
---   * flat commands -- `:CwdHere`, `:PowershellProfile`. Kept for muscle
---     memory; they predate the verb.
---   * the `:Lib` verb -- `:Lib helptags | cwd-here | ps-profile`, plus
---     `:Lib deps ...`. Composer-built, with `<Tab>` completion, and it
---     dogfoods `lib.nvim.bindings.usercmd.composer`.
---
--- Both dispatch into `lib.nvim_usrcmds.actions`, so they cannot drift.

local actions = require("lib.nvim_usrcmds.actions")

local M = {}

---Register `:CwdHere`.
---@return nil
function M.cwd_here()
  vim.api.nvim_create_user_command(
    "CwdHere",
    actions.cwd_here,
    { desc = "Set local cwd to the directory of the current buffer" }
  )
end

---Register `:PowershellProfile`.
---@return nil
function M.powershell_profile()
  vim.api.nvim_create_user_command(
    "PowershellProfile",
    actions.powershell_profile,
    { desc = "Open the active PowerShell profile in Neovim" }
  )
end

---Register the unified `:Lib <subcommand>` verb.
---
---Routes mirror which features are enabled, so the verb never advertises an
---action the flat set would also omit.
---@param o Lib.NvimUsrCmds.Options
---@return nil
function M.lib_verb(o)
  local routes = {
    { path = { "helptags" }, desc = "Regenerate all helptags now", run = actions.helptags },
    {
      path = { "cwd-here" },
      desc = "lcd to the current buffer's directory",
      run = actions.cwd_here,
    },
  }
  if o.powershell_profile then
    routes[#routes + 1] = {
      path = { "ps-profile" },
      desc = "Open the active PowerShell profile",
      run = actions.powershell_profile,
    }
  end

  -- `:Lib deps show|install` rather than a separate `:LibDeps` command: a
  -- second top-level name for a subordinate feature is exactly the
  -- `:VerbFeatureA`/`:VerbFeatureB` shape composer exists to replace.
  if o.deps then
    for _, route in ipairs(require("lib.nvim.deps").routes()) do
      routes[#routes + 1] = route
    end
  end

  require("lib.nvim.bindings.usercmd.composer").verb("Lib", {
    desc = "lib.nvim utility commands",
    routes = routes,
  })
end

return M
