# `lib.nvim.markdown.link_cursor`

Put the cursor where a freshly inserted markdown link still needs typing.

Plugins that insert `[title](path)` / `![alt](path)` used to leave the cursor
*behind* the link — the one place where nothing is left to write. The rule
here is "go where something is missing", then enter insert mode:

| Inserted link | Cursor goes |
|---|---|
| `![](assets/x.png)`, `[](https://…)`, `[]()` (title empty) | inside `[]` |
| `[name](path)` (title filled) | into the path, at its end (`path_cursor = "start"` for the start) |
| `[name]()` | inside `()` |

With several links in one insertion the **first** link decides. Text without a
link leaves the cursor behind the text, as before. The module never *builds* a
link — that stays with each caller, which knows its own path spelling.

```lua
local lc = require("lib.nvim.markdown.link_cursor")

-- insert and place in one go (row/col are 0-based, like nvim_buf_set_text)
lc.insert(buf, win, row, col, "![](assets/shot.png)")
lc.insert(buf, win, row, col, { "[a](one.md)", "[b](two.md)" }) -- a list of lines works too

-- you inserted yourself: only place the cursor
lc.place(win, row, col, text)

-- where would the cursor go? (pure, no buffer needed)
lc.locate("![](a.png)") --> { row = 0, col = 2, kind = "title" }
```

## Options

Module-wide defaults via `lc.setup({...})`; any call can pass the same table
as its last argument.

| Option | Default | Meaning |
|---|---|---|
| `enable` | `true` | `false` = cursor behind the inserted text, the old behavior |
| `startinsert` | `true` | enter insert mode after placing the cursor into a link |
| `path_cursor` | `"end"` | `"end"` or `"start"` of a filled path |

Invalid values are ignored, never raised. `insert` returns `false` (and does
nothing) for an invalid or non-modifiable buffer.
