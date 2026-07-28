# `lib.nvim.ui.hl`

Idempotent highlight-group definition, with optional namespace support.

## Usage

```lua
local hl = require("lib.nvim.ui.hl")

-- Global highlight group (namespace 0):
hl.set("MyPluginTitle", { fg = "#89b4fa", bold = true })

-- Namespaced by string name (created and cached on first use):
hl.set("MyPluginTitle", { fg = "#89b4fa" }, "my_plugin_ns")

-- Namespaced by an existing numeric id:
local ns_id = hl.namespace("my_plugin_ns")
hl.set("MyPluginTitle", { fg = "#89b4fa" }, ns_id)
```

### `namespace(name)`

Returns the numeric namespace id for `name`, creating it via
`vim.api.nvim_create_namespace(name)` on first call and caching it (module-
local table, keyed by `name`) for every subsequent call — repeated calls with
the same `name` are cheap and always return the same id.

### `set(group, opts, ns)`

Calls `vim.api.nvim_set_hl(ns_id, group, opts)`. `ns` may be a string (looked
up/created via `namespace()`), a number (used directly as the namespace id),
or omitted/`nil` (namespace `0`, i.e. the global highlight namespace). `opts`
is passed straight through to `nvim_set_hl` — see `:h nvim_set_hl` for its
fields (`fg`, `bg`, `bold`, `link`, …).
