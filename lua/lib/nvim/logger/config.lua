---@module 'lib.nvim.logger.config'
--- Default configuration for lib.nvim.logger. Kept in one place so the factory
--- and the global switches share a single source of truth.

local M = {}

---@type Lib.Logger.Options
M.defaults = {
  name = "lib",
  level = "debug", -- record DEBUG and above
  notify_level = "warn", -- only WARN+ reaches vim.notify
  file = nil, -- nil -> stdpath default (enabled), false -> disabled
  capture = true,
  history = 200,
  src = false,
  redact = nil,
}

return M
