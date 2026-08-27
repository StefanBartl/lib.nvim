# `lib.nvim.markdown.table`

Parse and re-render GFM pipe tables.

Extracted from **two** copies of the same engine — `markdown.nvim`'s
`core/table_fmt.lua` and `buffer-ctx.nvim`'s `format/table_fmt.lua`. Of the
seventeen functions they shared, four were byte-identical and nine more
differed only in line breaks. That was not a coincidence to tidy up later:
the two had already drifted, and each copy carried a fix the other lacked —
see the module doc comment in [`init.lua`](init.lua) for which copy was ahead
on what. This module takes the better half of each.

```
lib.nvim.markdown.table/
├── init.lua       -- the whole module (parsing, rendering, format_*)
└── @types/        -- LuaLS types (Lib.Markdown.Table.*)
```

Entry point is `require("lib.nvim.markdown.table")`.

## Design choices that carry over from the extraction

* **Width is `vim.fn.strdisplaywidth`, not `lib.lua.strings.width`.** The
  latter's `display_width` is pure Lua and decides ambiguous-width
  characters from its own tables; Neovim consults `'ambiwidth'` and the
  active encoding instead. Both original copies measured with
  `strdisplaywidth`, and these tables get written back into real files — a
  different measurement would silently reflow every table anybody has. The
  pure version is only the fallback for a non-Neovim host; `opts.width_fn`
  overrides both.
* **No notifications, no config lookup.** Every function returns; nothing is
  reported directly. `resolve_overrides` returns `map, warnings` instead of
  notifying — a caller decides how loud a config typo should be. This is
  what let the buffer- and file-level helpers (`format_buffer`,
  `format_at_cursor`, `format_file`) move into the module too, instead of
  staying behind as a third and fourth copy: a plugin wires config-read →
  call this module → notify around them.

## API

```lua
local T = require("lib.nvim.markdown.table")

local tables = T.parse(lines)             -- Lib.Markdown.Table[]
local tbl, err = T.at_cursor(tables, lnum)

local rendered = T.render(tbl, {
  header_align = "left", entry_align = "left",
  override_map = {},      -- col idx -> "left"|"center"|"right"
  width_fn = nil,          -- defaults to display_width
})

-- Whole-document convenience, all built on format_lines:
local out, count, warnings = T.format_lines(lines, opts)
local ok, err, count, warnings = T.format_buffer(bufnr, opts)
local ok, err, warnings = T.format_at_cursor(bufnr, opts)
local ok, err, count, warnings = T.format_file(path, opts)
```

Lower-level primitives (`display_width`, `pad_cell`, `is_table_line`,
`is_separator_line`, `parse_row`, `calc_widths`, `resolve_overrides`,
`trim`, `gen_separator`, `format_row`) are public too: `trim`/`gen_separator`/
`format_row` in particular exist because markdown.nvim's `table_wrap`
(soft-wrapping long cells) builds rows outside the normal parse → render
pipeline and needs the same primitives directly — exposing them here is what
avoided a third copy of *those*.

`opts.col_overrides` is `{ { col = 1 | "Name", align = "left" } }[]` — a
column named by 1-based index or by header text (case-insensitive). One that
matches nothing lands in the returned `warnings`, not silently dropped.

See [`TESTS/markdown_table_spec.lua`](../../../../../TESTS/markdown_table_spec.lua)
for the full behavioural contract, including what each original copy got
right that this module keeps.
