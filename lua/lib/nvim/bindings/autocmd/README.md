# `lib.nvim.bindings.autocmd`

Standardized autocommand creation on top of `vim.api.nvim_create_autocmd` —
automatic augroup handling, a defensive callback wrapper, and event/pattern
normalization helpers.

## Usage

```lua
local autocmd = require("lib.nvim.bindings.autocmd")

autocmd.create("BufWritePost", function(args)
  print("wrote", args.file)
end, {
  group = "my-plugin",   -- string: looked up/created via autocmd.group()
  pattern = "*.lua",
  once = false,
  nested = false,
})
```

`create`'s callback is always wrapped in `pcall`; an error inside it is
reported via `require("lib.nvim.notify")` (tagged `[lib.nvim.bindings.autocmd]`)
instead of aborting whatever fired the autocmd. `opts.desc` defaults to `""`
when omitted.

`pattern` and `buffer` are mutually exclusive in the underlying API — passing
`opts.buffer` here routes to buffer-local scoping and `opts.pattern` is
ignored, rather than both being merged (which would silently downgrade a
buffer-local request to a global `pattern = "*"`).

## Augroup management

```lua
autocmd.group("my-plugin")            -- create/lookup, no clearing
autocmd.group("my-plugin", true)      -- create/lookup, clear = true

autocmd.get_augroup("save", { prefix = "my-plugin", clear = true })
-- creates/looks up augroup "my-plugin.save"
```

`group(name, clear)` and `get_augroup(name, opts)` are two independent
caches (`groups` vs. an internal `cache` table, keyed differently — plain
name vs. `prefix.name`) — each memoizes by its own key so repeated calls with
the same name return the same augroup id without recreating it.

`autocmd.augroup` (from [`augroup.lua`](augroup.lua)) is a third, unrelated
one-off: `autocmd.augroup.create.clear(name)` always creates (or clears) a
namespaced augroup unconditionally, with no caching.

## Normalization helpers

```lua
autocmd.norm_events(user_events, { "BufEnter" })
-- returns user_events if it's a non-empty table, else the fallback

autocmd.norm_pattern(nil)     --> "*"
autocmd.norm_pattern("*.md")  --> "*.md"
```

Useful when a plugin's own config lets a user override `events`/`pattern`
but needs a guaranteed-valid value to hand to `nvim_create_autocmd`.
