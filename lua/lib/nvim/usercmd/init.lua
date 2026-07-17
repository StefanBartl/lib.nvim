---@module 'lib.nvim.usercmd'
-- =========================================================
-- User command helper utilities.
--
-- Standardized wrapper around nvim_create_user_command with
-- sane defaults, defensive execution and LuaLS annotations.
-- =========================================================

local notify = require("lib.nvim.notify").create("[lib.nvim.usercmd]")

local M = {}

---@param name string
---@param callback string|fun(args:Lib.UserCommand.Args)
---@param opts LibUserCommandOpts|nil
function M.create(name, callback, opts)
  opts = opts or {}

  if opts.desc == nil then
    opts.desc = ""
  end

  if opts.nargs == nil then
    opts.nargs = 0
  end

  -- Default to Neovim's native behavior (`force = true`): overwrite an
  -- existing command instead of raising E174. This keeps command creation
  -- idempotent under config hot-reload (e.g. NvChad's ReloadNvChad
  -- BufWritePost autocmd re-sources chadrc on every save).
  if opts.force == nil then
    opts.force = true
  end

  if type(callback) == "function" then
    local user_cb = callback
    callback = function(args)
      local ok, err = pcall(user_cb, args)
      if not ok then
        notify.error(("UserCommand '%s' failed:\n%s"):format(name, err))
      end
    end
  end

  vim.api.nvim_create_user_command(name, callback, opts)
end

---@type Lib.UsrCmd
return M
