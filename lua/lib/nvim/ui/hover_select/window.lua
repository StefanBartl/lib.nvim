---@module 'lib.nvim.ui.hover_select.window'
---@description Window creation and configuration for lib.nvim.ui.hover_select

local notify = require("lib.nvim.notify").create("[lib.nvim.ui.hover_select.window]")

local M = {}

local config = require("lib.nvim.ui.hover_select.config")
local api = vim.api

---Calculate longest line width in items
---@param items string[] List of items
---@return integer width Width in display columns
local function calculate_max_line_width(items)
  local max_width = 0

  for _, line in ipairs(items) do
    -- Use vim.fn.strdisplaywidth for accurate display width (handles multibyte chars)
    local width = vim.fn.strdisplaywidth(line)
    if width > max_width then
      max_width = width
    end
  end

  return max_width
end

---Calculate optimal window dimensions based on content
---@param items string[]|nil Items to display (needed for auto-width calculation)
---@param items_count integer
---@param width integer|nil
---@param height integer|nil
---@param auto_width boolean|"wrap"|nil
---@return integer width
---@return integer height
---@return boolean wrap
local function calculate_dimensions(items, items_count, width, height, auto_width)
  local dims = config.dimensions
  local wrap = false

  -- Calculate height
  local calc_height = height or items_count
  calc_height = math.max(dims.min_height, math.min(calc_height, dims.max_height))

  -- Calculate width based on auto_width setting
  local calc_width

  if auto_width == "wrap" then
    -- Wrap mode: use minimum width and enable wrapping
    calc_width = width or dims.min_width
    calc_width = math.max(dims.min_width, calc_width)
    wrap = true

  elseif auto_width == true and items ~= nil then
    -- Auto-width mode: size to longest line
    local content_width = calculate_max_line_width(items)

    -- Add padding for border
    content_width = content_width + dims.padding

    -- Get editor width as maximum
    local editor_width = vim.o.columns
    local max_usable_width = editor_width - 4  -- Leave some margin

    -- Use user width if specified, otherwise use content width
    calc_width = width or content_width

    -- Clamp between min and max
    calc_width = math.max(dims.min_width, calc_width)
    calc_width = math.min(calc_width, math.min(dims.max_width, max_usable_width))

  else
    -- Fixed width mode (default)
    calc_width = width or (dims.min_width + dims.padding)
    calc_width = math.max(dims.min_width, math.min(calc_width, dims.max_width))
  end

  return calc_width, calc_height, wrap
end

---@overload fun(bufnr: integer, win_config: table, win_options: table<string, any>): integer|nil
---@overload fun(bufnr: integer, win_config: table, win_options: table<string, any>, items: string[], auto_width: boolean|"wrap"|nil): integer|nil
---@param bufnr integer
---@param win_config table
---@param win_options table<string, any>
---@param items string[]|nil
---@param auto_width boolean|"wrap"|nil
---@return integer|nil winid
function M.create(bufnr, win_config, win_options, items, auto_width)
  -- Calculate dimensions
  local width, height, wrap = calculate_dimensions(
    items,
    win_config.items_count or 0,
    win_config.width,
    win_config.height,
    auto_width
  )

  -- Build window configuration
  local float_config = vim.tbl_deep_extend("force", config.default_win_config, {
    relative = win_config.relative or "cursor",
    width = width,
    height = height,
    row = win_config.row or 1,
    col = win_config.col or 0,
    title = win_config.title,
  })

  -- Create floating window
  local winid = api.nvim_open_win(bufnr, true, float_config)
  if winid == 0 then
    notify.error("lib.nvim.ui.hover_select: failed to create window")
    return nil
  end

  -- Override wrap setting if auto_width is "wrap"
  if wrap then
    win_options = vim.tbl_extend("force", win_options, { wrap = true })
  end

  -- Apply window-local options
  for option, value in pairs(win_options) do
    local success, err = pcall(api.nvim_set_option_value, option, value, { win = winid })
    if not success then
      notify.error(string.format("lib.nvim.ui.hover_select: failed to set window option '%s': %s", option, err))
    end
  end

  -- Setup autocommands for cleanup
  M._setup_autocommands(bufnr, winid)

  return winid
end

---Setup autocommands for automatic window cleanup
---@param bufnr integer Buffer number
---@param winid integer Window ID
---@private
function M._setup_autocommands(bufnr, winid)
  local augroup = api.nvim_create_augroup("HoverSelectWindow_" .. winid, { clear = true })

  -- Close window when leaving buffer
  api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if api.nvim_win_is_valid(winid) then
        api.nvim_win_close(winid, true)
      end
    end,
  })

  -- Handle window closure
  api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(winid),
    callback = function()
      if api.nvim_buf_is_valid(bufnr) then
        api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
  })
end

---@type Lib.UI.HoverSelect.Window
return M
