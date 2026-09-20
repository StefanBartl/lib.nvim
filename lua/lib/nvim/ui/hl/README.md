# `lib.nvim.ui.hl`

Idempotent highlight-group definition with optional namespace support, and
`persist()` — highlight state that survives a theme change.

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

### `persist(spec, opts)`

Applies `spec` now and again after every theme change, returning
`{ apply, detach }`.

A `:colorscheme` clears every user-defined highlight group and rebuilds the
built-in ones, so anything a plugin defined, derived or cached from those
colours is stale the moment it runs. The remedy is always the same four
lines, and across this fleet it had been written out by hand **19 times in
7 plugins** — with three real divergences between otherwise identical
blocks:

- **`OptionSet background` was almost always missing.** Switching
  `&background` selects the other half of a light/dark palette and does not
  always fire `ColorScheme`. One plugin handled it; six did not. It is on by
  default here.
- **Some sites never re-applied at all** — applied once at setup, so the
  first theme switch undid them permanently.
- **Some registered the autocmd but never applied immediately**, leaving the
  first paint to whatever event came next.

```lua
local hl = require("lib.nvim.ui.hl")

-- A static table of groups.
hl.persist({
  DiagnosticVirtualTextError = { bg = "NONE" },
  DiagnosticVirtualTextWarn  = { bg = "NONE" },
}, { name = "myplugin_diagnostics" })

-- Groups derived from whatever theme is active: the function is
-- re-evaluated on every change, so the values follow the theme.
hl.persist(function()
  local fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg
  return { MyDim = { fg = fg } }
end, { name = "myplugin_dim" })

-- No groups at all — drop a cache keyed on theme colours. Redefining
-- groups and invalidating a colour-derived cache are the same problem
-- shaped differently; of the 19 sites, 4 were the latter.
local handle = hl.persist(function()
  icon_cache = {}
end, { name = "myplugin_iconcache" })

handle.apply()   -- re-apply on demand
handle.detach()  -- remove both autocommands
```

#### `opts`

| Field | Default | |
| --- | --- | --- |
| `name` | *required* | Augroup name and description prefix. Also the identity: a second `persist()` with the same `name` **replaces** the first rather than stacking a second set of autocommands, so re-running a plugin's setup is safe. |
| `background` | `true` | Also re-apply on `OptionSet background`. |
| `ns` | global | Highlight namespace, passed through to `set()`. |
| `immediate` | `true` | Apply once on registration. `false` registers only. |

A `spec` function that returns nothing is a side-effect callback, not a
mistake. Errors inside it are caught and reported through `lib.nvim.notify`:
every other listener in the session is behind the same `ColorScheme` event,
and one broken highlight definition must not take it down.
