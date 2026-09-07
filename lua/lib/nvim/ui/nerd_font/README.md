# `lib.nvim.ui.nerd_font`

Nerd Font glyphs, gated on a user declaration rather than a guess — Neovim
cannot see the terminal's font, so nothing here pretends to detect one.

## Usage

```lua
local nf = require("lib.nvim.ui.nerd_font")

-- Declared once, by the user (kickstart.nvim's convention):
vim.g.have_nerd_font = true

nf.available()                          --> true (only if the user declared it)
nf.glyph("F0056", "?")                  --> the glyph, or "?" when not declared/too wide
nf.chars({ "", "", "" }, { "#", "#", "#" })  --> the rich set, or the fallback set
nf.sep("F0056", "|")                    --> " <glyph or |> " (padded separator)
```

### `available()`

`true` only when `vim.g.have_nerd_font` was explicitly set to `true` or `1`.
Default is off — an unset/false value means "assume no Nerd Font", never a
guess. The asymmetry is deliberate: guessing wrong fills the screen with
replacement boxes, while a missing glyph costs nothing as long as a caller
passes a fallback.

### `glyph(hex, fallback)`

Returns the codepoint at `hex` (e.g. `"F0056"`) when a Nerd Font is declared
**and** the glyph renders exactly one cell wide (`vim.fn.strdisplaywidth`,
the one part of "does this render" Neovim can actually answer); `fallback`
otherwise. `fallback` is required — a caller with nothing to fall back on
should not be reaching for a glyph.

### `chars(rich, fallback)`

Same gate as `glyph`, but for a whole ordered set at once — a sparkline
ramp, a set of box-drawing pieces, a spinner. Returns `rich` only when every
character in it renders one cell wide; a single bad character rejects the
whole set rather than being silently swapped out of it, so a row never ends
up mixing `rich` and `fallback` characters.

### `sep(hex, fallback, pad?)`

`glyph(hex, fallback)` padded on both sides (`pad`, default one space) — for
separators that need breathing room without a caller re-deriving that
padding at every call site.
