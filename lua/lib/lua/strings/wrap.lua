---@module 'lib.lua.strings.wrap'
--- Word-aware text centering, pure Lua.

local M = {}

---Center a single line of text within `width` columns (padded with spaces).
---If `str` is already >= width, it is returned unchanged.
---@param str string
---@param width integer
---@return string
function M.center_text(str, width)
  local len = #str
  if len >= width then
    return str
  end
  local total_pad = width - len
  local left = math.floor(total_pad / 2)
  local right = total_pad - left
  return string.rep(" ", left) .. str .. string.rep(" ", right)
end

---Center each line of a multi-line block within `width` columns.
---@param lines string[]
---@param width integer
---@return string[]
function M.center_text_lines(lines, width)
  local out = {}
  for i = 1, #lines do
    out[i] = M.center_text(lines[i], width)
  end
  return out
end

return M
