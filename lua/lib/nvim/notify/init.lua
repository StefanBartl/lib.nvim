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

--- Create a prefixed notify helper (standard mode, not scheduled)
---@param prefix string Notification prefix, e.g. "[neotree-fs-refactor]"
---@return Lib.Notify.Notifier
function M.create(prefix)
  -- Normalize prefix once
  if type(prefix) ~= "string" then
    prefix = ""
  end

  if prefix ~= "" and not prefix:match("%s$") then
    prefix = prefix .. " "
  end

  ---@type Lib.Notify.Notifier
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

---@type Lib.Notify
return M
