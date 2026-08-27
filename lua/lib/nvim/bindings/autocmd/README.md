# `lib.nvim.bindings.autocmd`

Standardized autocommand creation on top of `vim.api.nvim_create_autocmd` —
automatic augroup handling, a defensive callback wrapper, and event/pattern
normalization helpers.

### The count in the generated header

A generated file says how many autocmds the repository creates *without* going
through this module, because those cannot appear in the table and a reader who
is not told assumes the table is the whole list. That count is a static scan —
those call sites leave no runtime trace, which is precisely the problem with
them.

Two things it does *not* count, both learned from being wrong about them:

- **String literals and comments.** `debugging.nvim` names
  `nvim_create_autocmd` thirteen times and creates none; it is a module that
  *scans* for them. A plain substring count named the two cleanest repositories
  as the two worst offenders.
- **Lines marked `lib-docs: fallback`** (on the line or the one above it). The
  soft-dependency pattern — prefer this module, fall back to `vim.api` when lib
  is not installed — has a native call site that is *correct*. Mark it and it
  stops being reported:

  ```lua
  -- lib-docs: fallback
  vim.api.nvim_create_autocmd(event, opts)
  ```

It does not require a call parenthesis, so `local au = vim.api.nvim_create_autocmd`
is counted once rather than missed.

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
require("lib.nvim.bindings.autocmd").docs.write()
```

That is the whole call. Everything is inferred, and one of the guesses is
better than what you would write by hand:

| | inferred from |
| --- | --- |
| `root` | the caller's own source path (`…/lua/…` → the directory holding `lua/`), else cwd |
| `dir` | `<root>/lua/<plugin>/bindings/autocmd` |
| `filter` | records whose **source file** lies inside `root` |
| `note` | omitted; the header already states the snapshot caveat |

The filter is the interesting one. The obvious hand-written version tests the
augroup name (`r.group:match("^myplugin")`) and is quietly wrong for every
group that does not follow that convention — and nothing tells you, the rows
are simply missing. "Was this autocmd created from a file in this repo" is the
actual question and does not care what the groups are called.

Pass a field only where the guess is wrong — a repo with several plugins under
`lua/`, or a note recording which configuration produced the run:

```lua
require("lib.nvim.bindings.autocmd").docs.write({
  note = "Generated with the default configuration.",
})
```

`docs.check()` compares against what is on disk without writing, for CI — a
generated file nobody verifies goes stale, which is the failure this whole
registry exists to end. Pass it the *same* opts as `write`, since `note` and
`root` are part of the rendered output.

`docs.create_usercmd()` registers `:LibAutocmdDocs` and
`:LibAutocmdDocsCheck`. Put that one line in **your own config**, not in a
plugin: it is a tool for whoever is editing the repo, and a plugin shipping it
would put an identical command in every user's editor. Then, sitting in the
repo with the plugin loaded, the whole workflow is `:LibAutocmdDocs`.

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
