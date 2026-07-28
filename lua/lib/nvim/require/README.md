# `lib.nvim.require`

Safe and extended `require` utilities: a `pcall`-wrapped require, a
directory-batch loader with lifecycle-function dispatch, and a lazy-require
closure factory.

## `M.safe(name)`

```lua
local ok, mod_or_err = require("lib.nvim.require").safe("some.module")
if not ok then
  -- mod_or_err is the pcall error message
end
```

Returns `false, "invalid module name"` if `name` isn't a string; otherwise
`pcall(require, name)` and passes the result straight through.

## `M.dir(dir, calls)`

```lua
require("lib.nvim.require").dir("myplugin.modules")           -- calls setup({}) on each
require("lib.nvim.require").dir("myplugin.modules", "apply")  -- calls apply() on each
require("lib.nvim.require").dir("myplugin.modules", { "init", "start" })
require("lib.nvim.require").dir("myplugin.modules", "")       -- require only, call nothing
```

Non-recursively `require`s every `*.lua` file directly inside
`vim.fn.stdpath("config") .. "/lua/<dir>"` (module name derived as
`<dir>.<filename_without_extension>`), then optionally dispatches a lifecycle
function on each loaded module table:

* `calls == nil` (default) — call `mod.setup({})` if present.
* `calls` a string — call exactly that function name (empty string `""` means
  call nothing at all, require only).
* `calls` a `string[]` — call each listed name, in order.

Only functions that actually exist and are callable are invoked. `init.lua`
is always skipped (avoids double-loading aggregators), and **the calling
module itself is skipped** — resolved via `debug.getinfo(2, "S")` against the
caller's own source path, to prevent the classic `lua/lib/func.lua ->
require_dir("lib")` infinite-recursion trap where `lib.func` would otherwise
re-require itself. Every `require` and every dispatched call is wrapped in
`pcall`; failures are reported via `require("lib.nvim.notify")` (tagged
`[lib.nvim.require]`) rather than aborting the batch. If the directory
contains no `.lua` files, a warning is emitted and the function returns.

Note: this reads `dir` relative to the **user's Neovim config** directory
(`stdpath("config")`), not relative to lib.nvim's own `lua/` tree — it is a
helper for consumers of lib.nvim to batch-load their own plugin's modules.

## `M.lazy(module_name)`

```lua
local get_heavy = require("lib.nvim.require").lazy("myplugin.heavy_module")
-- ... later, on first actual use:
get_heavy().do_thing()
```

Returns a closure that `require`s `module_name` on first call and caches the
result for every call after that — a minimal alternative to
`lib.lua.lazy` for a single module.
