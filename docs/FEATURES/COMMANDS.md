# Commands, keymaps & automation

Standardized wrappers around Neovim's own command/autocmd/keymap APIs — sane
defaults, defensive callbacks, and (for the biggest surface here, the
subcommand composer) a whole declarative framework other plugins build their
own `:Verb` commands on top of.

## Defensive user commands

A drop-in replacement for `nvim_create_user_command`/
`nvim_buf_create_user_command` that survives config hot-reload (an existing
command is silently overwritten rather than raising `E174`) and never lets a
callback error escape uncaught.

- **Module:** `lib.nvim.usercmd` (`create`)
- **Config:** defaults applied when omitted — `opts.desc = ""`, `opts.nargs =
  0`, `opts.force = true`

```lua
local usercmd = require("lib.nvim.usercmd")
usercmd.create("MyCmd", function(args) print(args.fargs[1]) end, { nargs = "?" })
usercmd.create("TableView", handler, { buffer = true })  -- current-buffer-local
```

A function `callback` is wrapped in `pcall`; a failure is reported via
`lib.nvim.notify` (tagged `[lib.nvim.usercmd]`) naming the command, instead of
propagating the raw error.

## Subcommand composer

**The most widely-used module in the whole library — 30+ consuming plugins.**
Turns the `:VerbFeatureA`/`:VerbFeatureB` anti-pattern into
`:Verb feature-a`/`:Verb feature-b`: one declarative route-tree spec produces
one real user command with subcommand dispatch, `<Tab>` completion at every
level, and generated Markdown docs, all read from the same tree so behavior
and docs can never drift.

- **Tab:** true
- **Module:** `lib.nvim.usercmd.composer` (`verb`, fluent builder,
  `register_type`, `document`, `check_all`, `checkhealth`)
- **Usage:** `require("lib.nvim.usercmd.composer")`,
  `require("lib").composer`, or `require("lib").usercmd.composer`

### Basic route spec

```lua
local composer = require("lib.nvim.usercmd.composer")

composer.verb("Replace", {
  desc    = "Text replacement operations",
  default = function(ctx) require("replacer").replace_prompt() end,
  routes  = {
    { path = { "buffer" }, desc = "Replace within the current buffer",
      run = function(ctx) require("replacer").buffer() end },
    { path = { "cwd" }, args = { { name = "root", type = "DIR", optional = true } },
      run  = function(ctx) require("replacer").cwd(ctx.args.root) end },
  },
})
```

`:Replace <Tab>` completes `buffer | cwd`, bad input is reported with the
route's own usage instead of a raw command error. A fluent builder form
(`composer.verb("Replace"):desc(...):route(...):build()`) is equivalent.

### Argument types, flags, and bare `key=value`

Each declared argument carries both validation and `<Tab>` completion —
`STRING`, `INT`, `FLOAT`, `BOOL`, an `enum`, `PATH`/`DIR`/`FILE`/`BUFFER`, or a
custom type registered once via `composer.register_type`. Routes may
additionally declare `flags` (`--flag`/`-x`/`--flag=value`, parsed anywhere in
the tail, `--` sentinel stops parsing) and `kv` (bare `key=value`, no dashes)
— both optional and composable on the same route.

```lua
{ path = {}, args = { { name = "old", type = "STRING" }, { name = "new", type = "STRING" } },
  flags = { { name = "dry", bool = true }, { name = "engine", type = "STRING", enum = { "fzf", "telescope" } } },
  run = function(ctx) require("replacer").run(ctx.args.old, ctx.args.new, ctx.flags) end }
```

### The handler context (`ctx`)

Every route handler receives one `ctx` table: `ctx.args`/`ctx.pos` (coerced
positionals), `ctx.flags`, `ctx.kv`, `ctx.rest`, `ctx.path` (the matched
route), `ctx.bang`, `ctx.range` (`{ line1, line2, count, range, mode, col1,
col2 }` — `mode`/`col1`/`col2` filled in whenever a real range was given, so a
handler can tell charwise/linewise/blockwise Visual selections apart), and
`ctx.raw` (the untouched nvim callback args).

### Buffer-local and count-prefixed commands

`spec.buffer = true` (or an explicit bufnr) registers via
`nvim_buf_create_user_command` instead of the global table — typically wired
from a `FileType` autocmd. `spec.count = 0` (or a route's own `route.count`)
accepts a `:N Verb` count prefix, exposed as `ctx.range.count`.

### Documentation generation

The same route tree that drives dispatch and completion also generates docs,
so the two can never drift apart.

```lua
handle:document()                 -- one verb -> docs/BINDINGS/Usercmds.md
composer.document()               -- every registered verb -> default path
```

`composer.setup({ docs = { path = "...", mode = "section" } })` updates a
delimited block inside a larger hand-written file instead of overwriting it
whole (`mode = "replace"`, the default).

### Health checks per route

A route's `run` may be a module path string, required lazily on first
dispatch — so a broken module stays invisible until someone actually runs
that subcommand. `handle:check()` / `composer.check_all()` resolve every
route up front instead, and a route may declare its own `check` for anything
composer can't infer (an external CLI, a config file).

```lua
require("lib.nvim.usercmd.composer").checkhealth("Replace")  -- from your plugin's own health.lua
composer.notify_check_all()  -- notification-based alternative, no health.lua needed
```

## Defensive autocommands

Standardized autocommand creation on top of `nvim_create_autocmd` — automatic
augroup lookup/caching, a `pcall`-wrapped callback, and event/pattern
normalization so a plugin's own config can safely pass through user overrides.

- **Module:** `lib.nvim.autocmd` (`create`, `group`, `get_augroup`,
  `norm_events`, `norm_pattern`)

```lua
local autocmd = require("lib.nvim.autocmd")
autocmd.create("BufWritePost", function(args) print("wrote", args.file) end, {
  group = "my-plugin", pattern = "*.lua",
})
```

An error inside the callback is reported via `lib.nvim.notify` (tagged
`[lib.nvim.autocmd]`) instead of aborting whatever fired the event.
`opts.buffer` and `opts.pattern` are mutually exclusive, matching the
underlying API — passing `buffer` routes to buffer-local scoping and
`pattern` is ignored, rather than silently downgrading to a global `"*"`.
`autocmd.group(name, clear)` and `autocmd.get_augroup(name, opts)` are two
independently-memoized caches; `autocmd.augroup.create.clear(name)` is a
third, always-unconditional one-off.

## Keymap wrapper

A `vim.keymap.set` wrapper with sane defaults and defensive validation —
`require("lib.nvim.map")` returns the callable directly (the module *is* a
function, not a table to index into).

- **Module:** `lib.nvim.map`
- **Config:** defaults — `opts.noremap = true`, `opts.silent = true`,
  `opts.desc = ""`; `opts.buffer = true` normalizes to `0`

```lua
local map = require("lib.nvim.map")
map("n", "<leader>x", function() end, {}, "Do a thing")
```

On validation failure `vim.keymap.set` is never called — every failing field
is reported, plus the real caller's call site (not this wrapper's), so the
error message points at the actual bug.

## Native `.`-repeat wiring

Wires a function through `operatorfunc` so it repeats with a plain `.`, with
no `vim-repeat` dependency.

- **Module:** `lib.nvim.dotrepeat` (`run`, `repeatable`)

```lua
local dotrepeat = require("lib.nvim.dotrepeat")
vim.keymap.set("n", "gx", dotrepeat.repeatable(function() do_the_thing() end))
```

## Debounce primitives

A generic debounce built on the editor's own timer, plus a buffer-scoped
variant with one independent timer per buffer and automatic cleanup.

- **Module:** `lib.nvim.debounce` (`new`, `new_with_counter`),
  `lib.nvim.debounce.buffer` (`new`)

```lua
local debounce = require("lib.nvim.debounce")
local d = debounce.new(function() reindex() end, 200)
d.call()   -- coalesces rapid-fire calls into one after 200ms of quiet
```

`debounce.buffer.new` auto-arms a cleanup autocmd (`BufDelete`/`BufWipeout`
by default) so a per-buffer timer never outlives its buffer, and supports an
`adaptive` delay that scales with buffer size.
