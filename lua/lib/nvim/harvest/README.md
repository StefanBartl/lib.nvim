# `lib.nvim.harvest`

Building blocks for **"collect something from a scope, then show or export it"**
features.

```lua
local harvest = require("lib.nvim.harvest")
```

Three independent pieces. Use one, two, or all three — there is no pipeline
object to buy into and no registry to register with.

| Module            | Direction                                    |
| ----------------- | -------------------------------------------- |
| `harvest.scope`   | a scope token → `Lib.Harvest.Source[]`       |
| `harvest.render`  | headers + rows → GFM table / CSV / lines     |
| `harvest.sink`    | text → clipboard / file / scratch buffer / picker |

## Why this exists

The middle step — deciding what counts as a hit — is domain logic and stays
with the caller. The two steps *around* it were being reimplemented every
time. `markdown.nvim` alone carried two near-identical scope collectors
(`commands/links.lua` for `%`/`cwd`/`<file>`, `commands/markdown_links.lua`
for a directory tree), each with its own file filter, ignore handling, and
"read the file, remember which file it was" bookkeeping.

Deliberately **not** provided: a `run({ collect, transform, present })`
framework. Wrapping a four-line `for` loop in injected callbacks buys ceremony,
not reuse.

## `harvest.scope`

```lua
local scope = require("lib.nvim.harvest.scope")

scope.resolve("buffer")                                   -- current buffer
scope.resolve("buffers")                                  -- every listed, loaded buffer
scope.resolve("range", { line1 = 10, line2 = 20 })        -- part of a buffer
scope.resolve("cwd", { match = "%.md$" })                 -- files under getcwd()
scope.resolve("path", { path = "~/notes", recursive = false })

-- Free-form token, the way a user command receives it:
-- ""/"%" → buffer, "cwd"/"buffers" → themselves, anything else → a path.
scope.resolve_token(arg)
```

Returns `sources, err`. Each source is:

```lua
---@class Lib.Harvest.Source
---@field file  string|nil   absolute path, when it came from disk or a named buffer
---@field bufnr integer|nil  buffer it came from, when it came from a buffer
---@field lines string[]
---@field first integer      1-based line number of lines[1] in its file/buffer
```

`first` is what lets a caller report real line numbers for a partial scan —
without it, every hit in a visual selection would be reported as if the
selection started at line 1.

**Options** (`Lib.Harvest.ScopeOpts`): `bufnr`, `line1`/`line2`, `path`,
`recursive` (default `true`), `match` (a Lua pattern the basename must match),
`ignore` (defaults to [`lib.nvim.fs.ignore.list`](../fs/ignore/list/README.md)),
`max_files` (default 2000), `max_filesize` (default 1 MiB).

Files that are unreadable, oversized, or binary (a NUL-byte probe) are skipped
rather than raising, so one stray `.png` cannot abort a whole harvest. CRLF is
normalized, and a trailing newline does not produce a phantom final line.

## `harvest.render`

```lua
local render = require("lib.nvim.harvest.render")

render.markdown_table({ "File", "Link" }, rows, { align = { "l", "r" } })
render.csv({ "a", "b" }, rows)        -- RFC 4180 quoting
render.lines(rows, " — ")
```

Column widths are measured with `strdisplaywidth`, not `#`, so multibyte and
double-width text still lines up. Cell content is flattened to one line and
`|` is escaped — an unescaped pipe would silently split one cell into two.

`markdown.nvim`'s `tableview` renders tables that *already exist* in a buffer;
this goes the other direction (arbitrary rows → a table you can paste).

## `harvest.sink`

```lua
local sink = require("lib.nvim.harvest.sink")

sink.clipboard(text)                                    -- → ok, err
sink.file(text, "~/out.md")                             -- → ok, err
sink.scratch(text, { title = "Links", split = "vsplit" })
sink.select(items, { prompt = "Links", format = tostring }, function(item) … end)
```

`scratch` buffers are `buflisted = false` + `bufhidden = wipe`: a results view
is not a document, so it stays out of `:ls`, out of buffer pickers, and out of
session files, and disappears with its window.

`select` prefers [`lib.nvim.ui.kit.select`](../ui/kit/README.md) and falls back
to `vim.ui.select`.

## `harvest.emit`

The one convenience, because mapping a user-supplied `out=` token to a sink is
the part that would otherwise be copy-pasted verbatim:

```lua
harvest.emit(text, "clipboard")
harvest.emit(text, "file:/tmp/out.md")
harvest.emit(text, "table", { title = "Results" })
harvest.outputs()  --> completion candidates
```

Recognized: `buffer`/`table` (scratch buffer), `clipboard`/`clip`, `echo`,
`file:<path>`.

## Worked example

```lua
local harvest = require("lib.nvim.harvest")

local sources = harvest.scope.resolve_token("cwd", { match = "%.md$" })

local rows = {}
for _, src in ipairs(sources) do
  for i, line in ipairs(src.lines) do
    if line:match("TODO") then
      rows[#rows + 1] = { src.file or "[buffer]", src.first + i - 1, line }
    end
  end
end

harvest.emit(
  harvest.render.markdown_table({ "File", "Line", "Text" }, rows),
  "table"
)
```

## Used by

- [`open.nvim`](https://github.com/StefanBartl/open.nvim) — `:Open urlview` / `:UrlView`
