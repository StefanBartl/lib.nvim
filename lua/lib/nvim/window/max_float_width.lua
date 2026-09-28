---@module 'lib.nvim.window.max_float_width'
---The screen-width ceiling `make_scratch`'s own `resolve_dimensions` clamps
---every float's width to. Exported so a caller that derives a float's `col`
---from its width (to keep it right-anchored) can clamp to the exact same
---ceiling before computing `col` -- an unclamped width there would compute
---`col` for a wider float than the one `make_scratch` actually opens,
---pinning it to the wrong edge once a render exceeds the editor's width.
---@return integer
local function max_float_width()
  return math.max(1, vim.o.columns - 4)
end

return max_float_width
