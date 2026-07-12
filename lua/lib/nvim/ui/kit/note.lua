---@module 'lib.nvim.ui.kit.note'
--- Note component: a centered title + message float, auto-sized, closable with
--- q / <Esc>, with an optional auto-dismiss timeout. The first and simplest
--- component built on the surface primitive.

local surface = require("lib.nvim.ui.kit.surface")

local M = {}

--- Normalize a message (string or string[]) to buffer lines.
---@param message string|string[]
---@return string[]
local function to_lines(message)
  if type(message) == "table" then
    return message
  end
  if type(message) ~= "string" then
    return { tostring(message) }
  end
  return vim.split(message, "\n", { plain = true })
end

--- Open a note popup.
---@param opts Lib.UI.Kit.NoteOpts
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}

  local surf = surface.open({
    lines = to_lines(opts.message or ""),
    theme = opts.theme,
    title = opts.title,
    width = opts.width,
    height = opts.height,
    relative = opts.relative or "editor",
    nice_quit = true,
    enter = false,
    filetype = "lib-kit-note",
  })

  if not surf then
    return nil
  end

  local timeout = tonumber(opts.timeout)
  if timeout and timeout > 0 then
    vim.defer_fn(function()
      surf:close()
    end, timeout)
  end

  return surf
end

return M
