# `lib.nvim.bindings.usercmd`

Standardized wrapper around `nvim_create_user_command`/
`nvim_buf_create_user_command` with sane defaults and a defensive callback.

## Usage

```lua
local usercmd = require("lib.nvim.bindings.usercmd")

usercmd.create("MyCmd", function(args)
  print(args.fargs[1])
end, {
  nargs = "?",
  desc = "Do a thing",
})
```

Defaults applied when not set explicitly: `opts.desc = ""`, `opts.nargs = 0`,
and — notably — **`opts.force = true`**: an existing command with the same
name is silently overwritten (Neovim's native default) rather than raising
`E174`. This keeps command creation idempotent under config hot-reload setups
(e.g. a `BufWritePost` autocmd that re-sources config and re-registers
commands on every save). Pass `opts.force = false` to restore the raising
behavior.

A function `callback` is wrapped in `pcall`; a failure is reported via
`require("lib.nvim.notify")` (tagged `[lib.nvim.bindings.usercmd]`) naming the command,
instead of propagating the raw error. A string `callback` (a Vim Ex command
string) is passed through unwrapped, matching `nvim_create_user_command`'s
own accepted types.

## Buffer-local commands

```lua
usercmd.create("TableView", handler, { buffer = true })   -- current buffer
usercmd.create("TableView", handler, { buffer = 12 })     -- explicit bufnr
```

`opts.buffer` isn't a real `nvim_create_user_command` field — it's extracted
and removed from `opts` before the native call, and routes to
`nvim_buf_create_user_command` on the resolved buffer (`true` → current
buffer via `nvim_get_current_buf()`, or an explicit bufnr) instead of the
global command table.

## Subcommand composer

```lua
usercmd.composer.verb("Replace", { ... })
```

`usercmd.composer` is a lazy proxy onto `lib.nvim.bindings.usercmd.composer` — set up
via `__index` rather than an eager `require`, specifically to avoid a require
cycle (the composer itself depends on `usercmd.create`). It builds one user
command with subcommand routing, `<Tab>` completion, and generated docs from
a single declarative spec. See
[`composer/README.md`](composer/README.md) for the full surface
(`verb`, fluent builder, argument types, flags, `key=value` parsing,
`:document()`).
