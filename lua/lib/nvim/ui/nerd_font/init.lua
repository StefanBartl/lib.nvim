---@module 'lib.nvim.ui.nerd_font'
--- Nerd Font glyphs, and the one honest thing that can be said about them.
---@description
--- **Neovim cannot see the terminal's font.** That is the whole reason this
--- module exists, and it is measured rather than assumed: `strdisplaywidth()`
--- returns 1 for every codepoint tried, including `U+10FFFD` -- a
--- noncharacter no font contains. It consults Unicode width tables, never the
--- font. No API answers "does this glyph render", so anything calling itself a
--- Nerd Font *check* is a guess wearing a lab coat.
---
--- So availability is **declared**, once, by the user:
---
--- ```lua
--- vim.g.have_nerd_font = true
--- ```
---
--- Default is off. The asymmetry decides it: guessing wrong fills the screen
--- with replacement boxes, while a missing glyph costs nothing as long as
--- callers pass a fallback -- which `M.glyph` requires them to.
---
--- The width guard in `M.glyph` is a separate matter and does work: a glyph
--- that renders two cells wide throws off any centred or column-aligned
--- layout, and `strdisplaywidth` *can* answer that.

local M = {}

--- Has the user declared that a Nerd Font is in use?
---
--- `vim.g.have_nerd_font` is the convention this follows rather than invents;
--- it is what kickstart.nvim popularised and what several plugins already read.
---@return boolean
function M.available()
  return vim.g.have_nerd_font == true or vim.g.have_nerd_font == 1
end

--- The glyph for `hex`, or `fallback` when a Nerd Font was not declared.
---
--- `fallback` is required, not optional: a caller that has nothing to fall
--- back on should not be reaching for a glyph in the first place, and making
--- it an argument is what stops "no font" from silently becoming an empty
--- string in the middle of a statusline.
---
--- A glyph that renders wider than one cell is also refused. That check is
--- real -- unlike font detection, `strdisplaywidth` genuinely answers it --
--- and a two-cell glyph is what quietly shifts every column after it.
---@param hex string        # Codepoint in hex, e.g. "F0056".
---@param fallback string   # Used when no Nerd Font is declared, or the glyph is too wide.
---@return string
function M.glyph(hex, fallback)
  vim.validate("hex", hex, "string")
  vim.validate("fallback", fallback, "string")

  if not M.available() then
    return fallback
  end

  local ok, g = pcall(require("lib.lua.strings.convert.hex_to_string"), hex)
  if not ok or type(g) ~= "string" or g == "" then
    return fallback
  end
  if vim.fn.strdisplaywidth(g) ~= 1 then
    return fallback
  end
  return g
end

--- `M.glyph` with padding, for separators that need breathing room.
---@param hex string
---@param fallback string
---@param pad string|nil    # Defaults to a single space on each side.
---@return string
function M.sep(hex, fallback, pad)
  pad = pad or " "
  return pad .. M.glyph(hex, fallback) .. pad
end

return M
