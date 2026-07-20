# `lib.nvim.cross.fs.mutate`

Injection-safe file mutation primitives built directly on libuv — no shell
involved, so they are safe to use with untrusted or user-controlled paths.

Every mutation is routed through `retry`, which re-attempts the operation when
libuv reports a transient sharing error (`EPERM`, `EACCES`, `EBUSY`).

## Why retry

On Windows those three codes are routinely returned for a file that is
perfectly deletable a few milliseconds later — an open directory watcher, the
search indexer, OneDrive, or an AV scanner still holds a handle on it. A single
immediate failure is not evidence that the operation is impossible.

On POSIX these errors mean what they say, so `defaults.attempts` is `1` there
and this module stays a plain passthrough.

## Usage

```lua
local mutate = require("lib.nvim.cross.fs.mutate")

local ok, err = mutate.rename_file(old, new)
if not ok then
  vim.notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
end
```

All four primitives return libuv-style `(ok, err)` and take an optional
`RetryOpts` as their last argument.

### Releasing your own handles

A retry does not help if *your* process is the one holding the path open. Use
`on_retry` to drop those handles between attempts:

```lua
mutate.rename_file(old, new, {
  on_retry = function(attempt, err)
    require("lib.nvim.neotree.watch").release({ old })
  end,
})
```

### Tuning

```lua
mutate.delete_file(path, { attempts = 5, backoff_ms = 100 })

-- Or globally, e.g. on a network share:
mutate.defaults.attempts = 5
```

Backoff escalates per attempt (`50ms`, `100ms`, `200ms`, …): a watcher close
settles far faster than an AV scan, so a flat delay would be either wastefully
long for the common case or too short for the rare one.

## Notes

- The wait uses `vim.wait`, not `uv.sleep`. The delay is only useful if the
  event loop keeps running, since that is what lets pending libuv handle-close
  callbacks complete and release the handle that caused the failure.
- `mkdir_p` goes through `retry` for a uniform signature only. `vim.fn.mkdir`
  raises a Vim error (`Vim:E739: …`) carrying no libuv code, so the transient
  check never matches and it does not in practice retry.
