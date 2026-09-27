# `lib.nvim.output`

Channel-agnostic output facade: one notifier shape
(`info`/`warn`/`error`/`debug`/`notify`, plus `dump`) regardless of which
delivery channel a caller picks.

```lua
local out = require("lib.nvim.output").create("[myplugin]")
out.info("started")                          -- popup toast + history (the default)
out.dump({ "line 1", "line 2" }, "results")  -- viewer, on every channel

local echo_out = require("lib.nvim.output").create("[p]", { channel = "echo" })
echo_out.info("12/128")                      -- transient cmdline line, no history
```

## Channels

| Channel | Delegates to | Use it for |
|---|---|---|
| `"popup"` (default) | `lib.nvim.notify.create(prefix, { popup = true, ... })` | discrete events — the default, always explicit, never guessed from context |
| `"echo"` | `lib.nvim.echo.write` | transient progress/status lines |
| `"vim_notify"` | `lib.nvim.notify.create(prefix)` | plain `vim.notify`, no toast |

`create(prefix, opts)`'s `opts.source`/`opts.messages` are forwarded to the
`"popup"` channel (see `lib.nvim.notify.popup`'s own config); the other
built-in channels ignore them.

## `dump(lines, title)`

The `print()` replacement: identical across every channel, always opens
`lib.nvim.output.viewer` (a thin wrapper around `lib.nvim.ui.kit.viewer`)
rather than going through the channel's own delivery path. This is what a
`print(...)`-based debug dump migrates to — see `lib.nvim.output.viewer`.

## Adding a channel

```lua
require("lib.nvim.output").register_channel("my_channel", function(prefix, create_opts)
  return {
    notify = function(msg, level, opts) ... end,
    info = function(msg, opts) ... end,
    warn = function(msg, opts) ... end,
    error = function(msg, opts) ... end,
    debug = function(msg, opts) ... end,
    dump = function(lines, title) ... end,
  }
end)

require("lib.nvim.output").create("[p]", { channel = "my_channel" })
```

Resolved by name from `create(prefix, { channel = "my_channel" })` exactly
like the three built-in channels.

## Headless fallback

No UI attached (`#vim.api.nvim_list_uis() == 0`): every channel falls back to
`io.stderr:write`, regardless of `opts.channel` — so library or CI code that
happens to call through this facade does not error, or block waiting on a UI
that will never appear.
