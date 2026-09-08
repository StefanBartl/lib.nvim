---@meta
---@module 'lib.nvim.contextmenu.@types'

---One nvzone/menu-shaped entry: either a leaf action (`cmd`), a nested
---fly-out (`items`), or a separator (`name = "separator"`, no other field).
---@class Lib.ContextMenu.Item
---@field name string                Label, or the literal `"separator"`
---@field cmd? function|string       Leaf action: a callback, or an Ex command string
---@field items? Lib.ContextMenu.Item[]  Nested fly-out entries (mutually exclusive with `cmd`)
---@field rtxt? string               Right-aligned hint text (usually a default keymap)
---@field hl? string                 Optional highlight group override (nvzone/menu)

---Options for `require("lib.nvim.contextmenu").bind_buffer(bufnr, get_items, opts)`.
---@class Lib.ContextMenu.BindOpts
---@field keymap? string     Trigger key (default `"<RightMouse>"`)
---@field modes? string[]    Modes to bind in (default `{ "n", "v" }`)
---@field mouse? boolean     Pass `{ mouse = true }` to `menu.open` (default `true`)
---@field desc? string       Keymap description (default `"Context menu"`)

---@alias Lib.ContextMenu.ItemsProvider fun(): Lib.ContextMenu.Item[]

---Which component draws the menu. `"auto"` (the default) prefers nvzone/menu
---when installed and falls back to `lib.nvim.ui.kit.menu`.
---@alias Lib.ContextMenu.Renderer "auto"|"kit"|"nvzone"

---Options for `require("lib.nvim.contextmenu").open(items, opts)`.
---@class Lib.ContextMenu.OpenOpts
---@field mouse? boolean   Anchor at the mouse pointer (default `true`)
---@field title? string    Menu title (kit renderer only; nvzone/menu has none)
---@field theme? any       `Lib.UI.Kit.ThemeArg` (kit renderer only)

--- `lib.nvim.contextmenu` module surface.
---@class Lib.ContextMenu
---@field setup fun(opts?: { renderer?: Lib.ContextMenu.Renderer })
---@field renderer fun(): Lib.ContextMenu.Renderer
---@field entry fun(available: any, label: string, fn: function, rtxt?: string): Lib.ContextMenu.Item|nil
---@field group fun(out: Lib.ContextMenu.Item[], ...: Lib.ContextMenu.Item|nil): boolean
---@field submenu fun(label: string, items: Lib.ContextMenu.Item[]): Lib.ContextMenu.Item|nil
---@field open fun(items: Lib.ContextMenu.Item[]|string, opts?: Lib.ContextMenu.OpenOpts)
---@field bind_buffer fun(bufnr: integer, get_items: Lib.ContextMenu.ItemsProvider, opts?: Lib.ContextMenu.BindOpts)
