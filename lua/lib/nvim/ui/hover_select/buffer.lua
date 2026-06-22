---@module 'lib.nvim.ui.hover_select.buffer'
---@description Buffer creation and content management for lib.nvim.ui.hover_select

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select.buffer]")

local M = {}

local api = vim.api
local nvim_set_option_value = api.nvim_set_option_value

---Create a new buffer with the given items
---@param items string[] List of items to display
---@param buf_options table<string, any> Buffer options to apply
---@return integer|nil bufnr Buffer number, or nil on failure
function M.create(items, buf_options)
  -- Create new unlisted buffer
  local bufnr = api.nvim_create_buf(false, true)
  if bufnr == 0 then
    notify.error("lib.nvim.ui.hover_select: failed to create buffer")
    return nil
  end

  -- Set buffer content (requires modifiable=true temporarily)
  nvim_set_option_value("modifiable", true, { buf = bufnr })
  api.nvim_buf_set_lines(bufnr, 0, -1, false, items)

  -- Apply user-provided buffer options
  for option, value in pairs(buf_options) do
    local success, err = pcall(nvim_set_option_value, option, value, { buf = bufnr })
    if not success then
      notify.warn(string.format("lib.nvim.ui.hover_select: failed to set buffer option '%s': %s", option, err))
    end
  end

  return bufnr
end

---Update buffer content with new items
---@param bufnr integer Buffer number
---@param items string[] New items to display
---@return boolean success True if update succeeded
function M.update_content(bufnr, items)
  if not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Temporarily enable modifications
local was_modifiable = api.nvim_get_option_value("modifiable", { bufnr = bufnr })
  nvim_set_option_value("modifiable", true, { buf = bufnr })

  -- Update content
  local success = pcall(api.nvim_buf_set_lines, bufnr, 0, -1, false, items)

  -- Restore modifiable state
  nvim_set_option_value("modifiable", was_modifiable, { buf = bufnr })

  return success
end

---@type Lib.UI.HoverSelect.Buffer
return M
