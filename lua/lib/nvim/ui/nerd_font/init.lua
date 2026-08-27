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

--- Pick between two character sets: the rich one when a Nerd Font is
--- declared, the plain one otherwise.
---
--- For the cases where the unit is not one glyph but a *set* that has to be
--- consistent -- a sparkline ramp, a set of box-drawing pieces, a spinner.
--- Picking per character would let a row mix `█` with `#`, which reads
--- worse than either set alone.
---
--- Each character is width-checked like `M.glyph`: one that renders wider
--- than a cell shifts every column after it, and in a ramp that is every
--- subsequent row too. A single bad character rejects the whole set rather
--- than being swapped out of it, for the same consistency reason.
---@param rich string[]      # Preferred set, e.g. the block-element ramp.
---@param fallback string[]  # Used when no Nerd Font is declared, or `rich` is unusable.
---@return string[]
function M.chars(rich, fallback)
  vim.validate("rich", rich, "table")
  vim.validate("fallback", fallback, "table")

  if not M.available() or #rich == 0 then
    return fallback
  end
  for _, c in ipairs(rich) do
    if type(c) ~= "string" or vim.fn.strdisplaywidth(c) ~= 1 then
      return fallback
    end
  end
  return rich
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
