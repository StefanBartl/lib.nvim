# `lib.nvim.fs.open.url.system_opener` — **deprecated**

> **Use [`lib.nvim.cross.open_default`](../../../../cross/open_default/README.md) instead.**
> This module is now a thin compatibility shim over it, kept only so existing
> `.open(url)` call sites keep working while they migrate.

The two modules solved the same problem — "open a path/URL with the OS
default handler" — twice, independently. `open_default` is the more complete
one:

- it runs `expand_path` (`~`, `$VAR`, `%VAR%`), which this module never did;
- on WSL it translates a Linux path to its Windows equivalent via `wslpath`
  before handing it to `explorer.exe`, so a `/home/...` or `~/...` path
  actually opens. This module handed the raw Linux path straight to the
  opener.

No caller was using this module's extra `cfg` surface (`prefer_ui_open`,
`enable_windows_opener`, `open_cmd_*`) or its `vim.ui.open`-first dispatch, so
the shim drops them. Only `cfg.on_exit` is still honored — it is forwarded to
`open_default`'s own `opts.on_exit`.

## Migration

```lua
-- before
require("lib.nvim.fs.open.url.system_opener").open(url)
require("lib.nvim.fs.open.url.system_opener").open(url, { on_exit = f })

-- after
require("lib.nvim.cross.open_default")(url)
require("lib.nvim.cross.open_default")(url, { on_exit = f })
```

`is_like` / `is_ike` have no replacement yet — keep requiring this module for
those, or inline the pattern match.

## Returns (shim)

`M.open(url, cfg?)` returns `true` when an opener was **dispatched**, `false`
otherwise. Without `cfg.on_exit` the job is detached and fire-and-forget, so
`true` says nothing about whether the target actually opened.

`M.is_like(s)` is a quick heuristic predicate: true for `http(s)://`, `file://`,
`www.`-prefixed, or bare `name.tld`-shaped strings.

> `M.is_ike` is a misspelling from the original module and remains as a
> deprecated alias of `M.is_like`. New code should use `is_like`.
