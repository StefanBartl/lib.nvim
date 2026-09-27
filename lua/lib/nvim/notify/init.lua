---@module 'lib.nvim.notify'
---@description Generic notification factory for Neovim configs
---
--- Allows per-module prefix configuration while mirroring vim.notify semantics.
--- Also provides safe notification methods for fast event contexts.
---
--- Usage:
---   local notify = require("lib.nvim.notify").create("[my-plugin]")
---   notify.info("Operation completed")
---
--- Safe usage (from fast events):
---   local safe = require("lib.nvim.notify").safe
---   safe.schedule("Message from fast context", vim.log.levels.INFO)

require("lib.nvim.notify.@types")

local M = {}

-- Global default for the `popup` option of `create()`, set via `M.setup`.
-- Read at *call* time inside `notifier.notify` (not at `create()` time): a
-- notifier is typically built once at module load
-- (`local notify = require("lib.nvim.notify").create(...)`), and resolving
-- the default there would freeze it to whatever was configured before that
-- module happened to load -- the same load-time-binding trap `popup.lua`'s
-- own docs warn about, one layer up.
local default_popup = false

--- Changes module-wide defaults.
---@param opts? { popup?: boolean } `popup = true` makes `create()` default to
---popup delivery for notifiers that don't set `popup` explicitly themselves
---@return nil
function M.setup(opts)
  opts = opts or {}
  if opts.popup ~= nil then
    default_popup = opts.popup and true or false
  end
end

--- Create a prefixed notify helper (standard mode, not scheduled)
---@param prefix string Notification prefix, e.g. "[neotree-fs-refactor]"
---@param create_opts? Lib.Notify.CreateOpts `popup = true`/`false` shows messages as a corner toast with history (see lib.nvim.notify.popup) instead of `vim.notify`; omitted, it follows the global default set via `M.setup({ popup = ... })` (default: false)
---@return Lib.Notify.Notifier
function M.create(prefix, create_opts)
  local popup_opt = create_opts and create_opts.popup
  local source = create_opts and create_opts.source
  local messages = create_opts and create_opts.messages

  -- Normalize prefix once
  if type(prefix) ~= "string" then
    prefix = ""
  end

  if prefix ~= "" and not prefix:match("%s$") then
    prefix = prefix .. " "
  end

  -- Deliberately not `---@type Lib.Notify.Notifier`: the table is filled
  -- below, so declaring the class on the empty literal is a `missing-fields`.
  -- The `@return` above is what checks the finished table.
  local notifier = {}

  ---Core notify function
  ---@param msg string
  ---@param level? integer
  ---@param opts? table
  function notifier.notify(msg, level, opts)
    if type(msg) ~= "string" then
      msg = tostring(msg)
    end

    level = level or vim.log.levels.INFO
    opts = opts or {}

    local popup = popup_opt
    if popup == nil then
      popup = default_popup
    end
    if popup then
      require("lib.nvim.notify.popup").deliver(
        prefix .. msg,
        level,
        { source = source, messages = messages, timeout = opts.timeout }
      )
      return
    end

    vim.notify(prefix .. msg, level, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.info(msg, opts)
    notifier.notify(msg, vim.log.levels.INFO, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.warn(msg, opts)
    notifier.notify(msg, vim.log.levels.WARN, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.error(msg, opts)
    notifier.notify(msg, vim.log.levels.ERROR, opts)
  end

  ---@param msg string
  ---@param opts? table
  function notifier.debug(msg, opts)
    notifier.notify(msg, vim.log.levels.DEBUG, opts)
  end

  return notifier
end

-- Export safe notification utilities
M.safe = require("lib.nvim.notify.safe")

-- Export popup delivery (toast + history)
M.popup = require("lib.nvim.notify.popup")

-- Export log-level resolution (also usable standalone at its leaf path,
-- e.g. from lib.nvim.logger)
M.resolve_log_level = require("lib.nvim.notify.resolve_log_level")

---@type Lib.Notify
return M
