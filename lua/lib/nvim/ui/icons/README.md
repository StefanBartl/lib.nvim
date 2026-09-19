# `lib.nvim.ui.icons`

File icons as data: a glyph, a colour and a name for a file, an extension or
a filetype — without a plugin behind it. A curated subset of
nvim-web-devicons' default set (MIT) lives in `data.lua`; the plugin, when it
is installed, is still asked first because it knows more.

## Usage

```lua
local icons = require("lib.nvim.ui.icons")

local glyph, color, name = icons.get("init.lua")          --> "", "#51a0cf", "Lua"
icons.get("noext", "typescript")                           --> filetype as the last resort
icons.get("thing.zzz")                                     --> the generic file icon
icons.get("thing.zzz", nil, { default = false })           --> nil
icons.get("init.lua", nil, { prefer_plugin = false })      --> this table, plugin or not
icons.get("init.lua", nil, { fallback = "*" })             --> "*" when no Nerd Font is declared

icons.lookup("package.json")     --> the raw entry { icon, color, name }, or nil
icons.by_filetype("python")      --> the same, by filetype
icons.hl_group("Lua", "#51a0cf") --> "LibIcon_Lua", created with that foreground
icons.counts()                   --> { extensions = …, filenames = …, filetypes = … }
```

## Resolution

1. nvim-web-devicons' `get_icon_color(name, ext)` when the plugin is loaded
   and `prefer_plugin` is not `false`;
2. `data.by_filename[base]` — exact name, `.gitignore`, `package.json`;
3. `data.by_extension` — the longest matching extension first, so `d.ts` is
   tried before `ts`;
4. `data.by_filetype[filetype]`;
5. `data.default`, unless `default = false`.

The glyph goes through `lib.nvim.ui.nerd_font`'s gate: with no
`vim.g.have_nerd_font` declared it is replaced by `fallback` (default `""`),
the colour and name are returned either way.

## The table

`data.lua` is generated, not hand-written: ~150 extensions, ~90 file names
and the full filetype map, picked from the devicons default set for what a
statusline or a tree meets in a working week. Add a line when one is missing;
the shape is `["ext"] = { icon = "…", color = "#rrggbb", name = "…" }`.
