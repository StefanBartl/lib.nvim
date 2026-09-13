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

  -- Buffer-local registration: opts.buffer = true (current buffer) or an
  -- explicit bufnr routes to nvim_buf_create_user_command instead of the
  -- global nvim_create_user_command. Extracted before the real API call
  -- since `buffer` isn't a real nvim_create_user_command opts field.
  local bufnr = opts.buffer
  opts.buffer = nil

  if type(callback) == "function" then
    local user_cb = callback
    callback = function(args)
      local ok, err = pcall(user_cb, args)
      if not ok then
        notify.error(("UserCommand '%s' failed:\n%s"):format(name, err))
      end
    end
  end

  if bufnr then
    local buf = (bufnr == true) and vim.api.nvim_get_current_buf() or bufnr
    vim.api.nvim_buf_create_user_command(buf, name, callback, opts)
  else
    vim.api.nvim_create_user_command(name, callback, opts)
  end
end

-- Subcommand composer (`:Verb sub sub ARG` + completion + docgen). Exposed
-- lazily to avoid a require cycle: the composer needs `usercmd.create`, so it
-- must be reachable from here without eagerly loading it at module scope.
---@type Lib.UserCmd.Composer
M.composer = setmetatable({}, {
  __index = function(_, k)
    return require("lib.nvim.usercmd.composer")[k]
  end,
})

---@type Lib.UsrCmd
return M
