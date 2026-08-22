---@module 'lib.nvim_usrcmds'
--- Utility user commands that don't belong in a more specific plugin.
--- Each command is opt-in and can be toggled independently in setup().
---
--- Two surfaces over the same actions:
---   * flat commands  — :CwdHere, :PowershellProfile (kept for muscle memory)
---   * the :Lib verb  — :Lib cwd-here | ps-profile | helptags (composer-built,
---                      with <Tab> completion; dogfoods lib.nvim.usercmd.composer)

require("lib.nvim_usrcmds.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim_usrcmds]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

---@type Lib.NvimUsrCmds.Options
local defaults = {
  helptags = true,
  cwd_here = true,
  powershell_profile = vim.fn.has("win32") == 1,
  lib_verb = true,
  deps = true,
}

-- ── Shared actions ──────────────────────────────────────────────────────────
-- The command bodies live here so the flat commands and the :Lib verb dispatch
-- to the exact same behavior.

-- FIX: neotree/nvimtree/netrw does not auto-refresh after lcd — trigger a
-- manual refresh in the file-tree plugin if needed.
-- NOTE; Ja das wird jedenfalls benötigt, ist mir schon mehrmals aufgefallen, dass dder fieltree ein refresh benötigte. Umsetzen!
---@internal
---Sets the local (window) cwd to the directory of the current buffer.
local function action_cwd_here()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    return
  end
  local dir = vim.fn.fnamemodify(bufname, ":p:h")
  vim.cmd("lcd " .. vim.fn.fnameescape(dir))
end

---@internal
---Opens the active PowerShell profile ($PROFILE) in Neovim.
local function action_powershell_profile()
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

---@internal
---Regenerates helptags for all installed plugins.
local function action_helptags()
  vim.cmd("helptags ALL")
end

-- ── Flat commands (unchanged surface) ───────────────────────────────────────

---@internal
---Regenerate helptags after lazy.nvim actually changed something on disk.
---
---This used to hang on `LazyDone`, which fires on *every* start. `helptags
---ALL` walks every installed plugin's doc/ directory and rewrites its tags
---file unconditionally -- measured at 229ms with ~116 plugins, and the second
---run in the same session costs the same, because nothing about it is
---incremental. Paying that on every launch buys nothing: help files only
---change when a plugin is installed or updated, and those are exactly the
---events below.
---
---`:Lib helptags` (and the flat `:Helptags`-style route) still regenerates on
---demand, for the case where something changed outside lazy's knowledge.
local function register_helptags()
  autocmd.create("User", function()
    action_helptags()
  end, {
    pattern = { "LazyInstall", "LazyUpdate", "LazySync" },
    desc = "[lib.nvim_usrcmds] regenerate helptags after lazy.nvim installs/updates plugins",
  })
end

---@internal
---Registers the :CwdHere user command.
local function register_cwd_here()
  vim.api.nvim_create_user_command(
    "CwdHere",
    action_cwd_here,
    { desc = "Set local cwd to the directory of the current buffer" }
  )
end

---@internal
---Registers the :PowershellProfile user command.
local function register_powershell_profile()
  vim.api.nvim_create_user_command(
    "PowershellProfile",
    action_powershell_profile,
    { desc = "Open the active PowerShell profile in Neovim" }
  )
end

-- ── :Lib verb (composer-built) ──────────────────────────────────────────────

--- Register the unified `:Lib <subcommand>` verb via the composer. Routes are
--- included to mirror which features are enabled, so the verb never advertises
--- an action the flat set would also omit.
---@param o Lib.NvimUsrCmds.Options
local function register_lib_verb(o)
  local routes = {
    { path = { "helptags" }, desc = "Regenerate all helptags now", run = action_helptags },
    {
      path = { "cwd-here" },
      desc = "lcd to the current buffer's directory",
      run = action_cwd_here,
    },
  }
  if o.powershell_profile then
    routes[#routes + 1] = {
      path = { "ps-profile" },
      desc = "Open the active PowerShell profile",
      run = action_powershell_profile,
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

  require("lib.nvim.usercmd.composer").verb("Lib", {
    desc = "lib.nvim utility commands",
    routes = routes,
  })
end

---Sets up the opt-in utility user commands per `opts`.
---@param opts Lib.NvimUsrCmds.Options|nil
function M.setup(opts)
  local o = vim.tbl_extend("force", defaults, opts or {})
  if o.helptags then
    register_helptags()
  end
  if o.cwd_here then
    register_cwd_here()
  end
  if o.powershell_profile then
    register_powershell_profile()
  end
  if o.lib_verb then
    register_lib_verb(o)
  end
end

return M
