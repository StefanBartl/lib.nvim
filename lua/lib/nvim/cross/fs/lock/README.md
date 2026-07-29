# `lib.nvim.cross.fs.lock`

Find out *who* is holding a file open on Windows — the diagnostic counterpart
to [`lib.nvim.cross.fs.mutate`](../mutate/README.md), which can only report
*that* a mutation failed.

## Why

`mutate` surfaces `EBUSY` / `EPERM` / `EACCES`, libuv's rendering of
`ERROR_SHARING_VIOLATION`. The code says a process has the file open without
`FILE_SHARE_DELETE`, but not which one — and the intuitive suspect is the wrong
one: an open buffer never locks a file, because Neovim closes it after reading
and keeps only its swap file open. Real candidates are antivirus scanners, the
search indexer, OneDrive, a directory watcher — or a leaked `fs_event` handle
inside your own Neovim, which no retry can ever outwait (see
[`lib.nvim.neotree.watch`](../../../neotree/watch/README.md)).

Answering that requires the Windows Restart Manager (`rstrtmgr.dll`) — the API
installers use to ask "please close these applications first". It needs no
administrator rights.

## Usage

```lua
local lock = require("lib.nvim.cross.fs.lock")

-- Is the file locked *right now*? (synchronous, works on every platform)
local ok, err = lock.probe(path)

-- Who holds it? (asynchronous — spawns PowerShell; Windows only)
lock.who(path, function(holders, err)
  for _, h in ipairs(holders or {}) do
    print(h.pid, h.name, h.app)  -- 49324  pwsh  PowerShell 7
  end
end)

-- Both, pre-rendered as a report
lock.report(path, function(lines) print(table.concat(lines, "\n")) end)
```

| Function | Notes |
|---|---|
| `supported()` | `true` on Windows. `probe` works everywhere; only holder lookup is Windows-only. |
| `probe(path)` | Renames the file aside and back, returning `(ok, err)`. Restores on success; a failed *restore* is reported as an error naming the parked path. |
| `who(path, cb)` | `cb(holders, err)`; `holders` is a possibly-empty list of `{ pid, name, app }`. |
| `report(path, cb)` | `cb(lines)` — path facts + probe + holders, uniformly worded. |

`probe` renames rather than opens on purpose: a rename is the operation that
actually trips over a missing `FILE_SHARE_DELETE`, so a reader-only lock that
would never have broken anything does not raise a false alarm.

## Reading the result

| Probe | Holders | Meaning |
|---|---|---|
| not renameable | a foreign process | That process is the cause; nothing a retry can fix. |
| not renameable | your own `nvim` | A handle leaked inside this Neovim — a watcher that was never `:close()`d. |
| not renameable | none | Kernel-level lock not registered with the Restart Manager. |
| renameable | any | The lock was transient and is already gone — exactly what `mutate`'s retry budget exists for. |
