---@meta
---@module 'lib.nvim.ui.list.@types'

--- One entry of a quickfix or location list, as `setqflist()` accepts it.
--- Mirrors `:h setqflist-what`; every field is optional because Vim itself
--- treats them that way -- an entry with only `text` is legal and renders as a
--- non-navigable line.
---@class Lib.UI.List.Item
---@field filename? string Path of the entry; alternative to `bufnr`.
---@field bufnr? integer Buffer of the entry; alternative to `filename`.
---@field lnum? integer 1-based line.
---@field end_lnum? integer 1-based end line of a multi-line entry.
---@field col? integer 1-based column.
---@field end_col? integer 1-based end column.
---@field vcol? integer Non-zero: treat `col` as a display column.
---@field text? string The line shown in the list.
---@field type? string Single-letter kind, e.g. `"E"`, `"W"`, `"I"`, `"N"`.
---@field nr? integer Error number.
---@field valid? integer Non-zero marks the entry as navigable.
---@field module? string Shown instead of the filename when set.
---@field pattern? string Search pattern locating the entry instead of `lnum`.
---@field user_data? any Carried through untouched; readable via `getqflist()`.

--- Options for `lib.nvim.ui.list.set`.
---
--- Deliberately all-optional: the no-argument call clears the quickfix list
--- and opens it, which is a meaningful thing to want.
---@class Lib.UI.List.Opts
---@field items? Lib.UI.List.Item[] Entries to place. Defaults to `{}`, which clears the list.
---@field title? string Title shown in the list's status line.
---@field loclist? boolean|integer `true` for the current window's location list, a window id for that window's, `false`/`nil` for the quickfix list.
---@field action? '" "'|'"r"'|'"a"' `" "` pushes a new list (default, keeps `:colder` history), `"r"` replaces the current one, `"a"` appends to it.
---@field open? boolean|'"auto"' Open the list window afterwards. `true` (default) always, `"auto"` only when there is at least one entry, `false` never.
---@field focus? '"list"'|'"source"' Where the cursor ends up. `"list"` (default) is what bare `:copen` does; `"source"` hands focus back to the window the call came from.
---@field height? integer Window height passed to `:copen`/`:lopen`.

---@class Lib.UI.List
---@field set fun(opts?: Lib.UI.List.Opts): integer
---@field qf fun(items: Lib.UI.List.Item[], title?: string, opts?: Lib.UI.List.Opts): integer
---@field loc fun(items: Lib.UI.List.Item[], title?: string, opts?: Lib.UI.List.Opts): integer

return {}
