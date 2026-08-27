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

## What fires when — `registered()` / `by_event()`

Every autocmd created through `create()` is recorded, so a plugin never has
to maintain its own list of "what fires when":

```lua
local au = require("lib.nvim.bindings.autocmd")

au.registered()                          -- every record, creation order
au.registered({ event = "BufWritePost" })
au.registered({ group = "filetree_preview" })
au.by_event()                            -- grouped: { FileType = { … }, … }
```

Each record carries `events`, `group`, `pattern`/`buffer`, `desc`, `once` and
`src` — the `file:line` of the call site, because "something re-highlights on
CursorMoved" is only half an answer; the other half is which file to open.

Recorded rather than catalogued by hand, because a hand-written mirror
drifts: filetree's claimed fourteen entries against forty-six real
registrations, and nothing anywhere said so. Clearing an augroup
(`group(name, true)`) drops that group's records with it, so a re-`setup()`
does not make the list grow.

## Writing it into `bindings/` — `docs.write()`

If you want the overview as files in the repo rather than a runtime call —
"everything the plugin binds lives under `bindings/`" — `docs` renders the
registry as markdown, one file per event family:

```lua
require("lib.nvim.bindings.autocmd").docs.write({
  dir    = repo .. "/lua/myplugin/bindings/autocmd",
  root   = repo,                       -- source paths become repo-relative
  filter = function(r)                 -- only this plugin's records
    return type(r.group) == "string" and r.group:match("^myplugin") ~= nil
  end,
  note   = "Generated with the default configuration.",
})
```

`docs.check(opts)` compares against what is on disk without writing, for CI —
a generated file nobody verifies goes stale, which is the failure this whole
registry exists to end. Pass it the *same* opts as `write`.

Markdown, not Lua: a `.lua` file that is really a listing pretends to be code
that runs, and the next reader goes looking for its callers.

**Never call this from `setup()`.** Writing files is a side effect a plugin
should not perform unasked, and the directory it would write into is the
*installed* plugin directory — your own repo while developing, somebody else's
plugin-manager-owned tree in every other case. Put it behind a command of your
own, or run it from CI.

## Normalization helpers

```lua
autocmd.norm_events(user_events, { "BufEnter" })
-- returns user_events if it's a non-empty table, else the fallback

autocmd.norm_pattern(nil)     --> "*"
autocmd.norm_pattern("*.md")  --> "*.md"
```

Useful when a plugin's own config lets a user override `events`/`pattern`
but needs a guaranteed-valid value to hand to `nvim_create_autocmd`.
