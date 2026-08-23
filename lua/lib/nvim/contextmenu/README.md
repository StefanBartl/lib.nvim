# `lib.nvim.contextmenu`

Building blocks for [nvzone/menu](https://github.com/nvzone/menu)-shaped
context-menu entries: a self-gating item builder (`entry`/`group`/`submenu`)
plus a mouse-trigger binder (`bind_buffer`). Soft dependency throughout —
`menu` is only `require()`d when a bound trigger actually fires, and a
missing install degrades to a single session-wide notify, never an error.

## Two integration shapes

**"Owns its buffer"** — a plugin-created UI (a tree, a dashboard, a
list-view). The plugin ships both an item builder and its own trigger,
bound directly on the buffer it creates. Live reference: `filetree.nvim`
(`lua/filetree/integrations/menu.lua` +
`lua/filetree/features/ui/context_menu/init.lua`).

```lua
-- integrations/menu.lua
local contextmenu = require("lib.nvim.contextmenu")

function M.items()
  local out = {}
  contextmenu.group(out,
    contextmenu.entry(feature("x") ~= nil, "  Do X", do_x, "<leader>x"),
    contextmenu.entry(feature("y") ~= nil, "  Do Y", do_y)
  )
  return out
end

function M.submenu(label)
  local items = M.items()
  if #items == 0 then return nil end
  return contextmenu.submenu(label or "  MyPlugin", items)
end
```

```lua
-- features/ui/context_menu/init.lua, wherever the plugin's own buffer is created
local contextmenu = require("lib.nvim.contextmenu")
local items_mod = require("myplugin.integrations.menu")

contextmenu.bind_buffer(bufnr, items_mod.items, {
  desc = "MyPlugin: right-click context menu",
})
```

**"Contributes only"** — the plugin's actions apply to ordinary
filetype-scoped or condition-scoped buffers it doesn't own. It ships only
`integrations/menu.lua` (`items`/`submenu`), with **no trigger code and no
`nvzone/menu` dependency at all** — a host (typically the user's own
RightMouse dispatcher) composes `submenu(...)` into its own menu when the
relevant condition holds. Live reference: `markdown.nvim`
(`lua/markdown/integrations/menu.lua`, composed by the user's
`config/menu/mappings.lua`).

## Functions

```lua
local contextmenu = require("lib.nvim.contextmenu")

contextmenu.entry(available, label, fn, rtxt)  -- {name,rtxt,cmd} or nil
contextmenu.group(out, entry, entry, nil, entry)  -- varargs; appends non-nil items, separator between groups
contextmenu.submenu(label, items)              -- {name=label, items=items} or nil if items is empty
contextmenu.bind_buffer(bufnr, get_items, opts) -- buffer-local <RightMouse>, soft-requires "menu"
```

See `@types/init.lua` for full field documentation (`Lib.ContextMenu.Item`,
`Lib.ContextMenu.BindOpts`).

## Design notes

- `group` takes varargs, not a table: `{ entry(...), nil, entry(...) }` loses
  everything past the first gap under `ipairs`/`#` (a table with holes has no
  defined length in Lua), silently dropping later entries whenever an
  earlier one in the same group gates off. Varargs don't have that problem —
  `select('#', ...)` counts every position, nil or not.
- `entry`/`group`/`submenu` never touch `nvzone/menu` — they build a plain
  data structure. Only `bind_buffer` (and, for "contributes only" plugins, the
  host composing the menu) ever calls `require("menu")`, so a plugin can call
  `entry`/`group`/`submenu` unconditionally regardless of whether nvzone/menu
  is installed.
- `bind_buffer` soft-requires `menu` at trigger time, not at bind time — safe
  to call from a plugin's setup path even when nvzone/menu isn't present; the
  keymap becomes an inert no-op (one notify per session) until it is.
- Not a fit for `lib.nvim.ui.kit.menu` (`lua/lib/nvim/ui/kit/menu.lua`): that
  component is cursor-anchored (`relative = "cursor"`), not mouse-anchored —
  it doesn't give nvzone/menu's `{ mouse = true }` pointer positioning that
  `<RightMouse>` needs. Use `ui.kit.menu` for keyboard-triggered action lists,
  `contextmenu` for anything meant to open at the mouse pointer.
