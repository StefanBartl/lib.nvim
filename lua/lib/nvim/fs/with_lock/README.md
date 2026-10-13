# `lib.nvim.fs.with_lock`

Run a function while holding an **advisory lock** on a path: a hidden
`.<name>.lock` file next to it, created exclusively
([`create_exclusive`](../create_exclusive/README.md)). Every process that
read-modify-writes the same file (an agent's command line and an editor plugin)
goes through it, so two of them never start from the same text and drop each
other's change. It serialises the *cooperating* writers only; an editor with the
file open is not one of them. Moved here from `tasks_nvim.fsio.with_lock`
(tasks.nvim@921a0c4).

Not to be confused with [`lib.nvim.cross.fs.lock`](../../cross/fs/lock/README.md),
which diagnoses who holds a file open on Windows.

```lua
local with_lock = require("lib.nvim.fs.with_lock")

local res, err, info = with_lock(path, function()
  -- read, change, write
  return "done"
end, { wait_ms = 500 })

if res == nil and info and info.retryable then
  -- somebody else is writing right now: ask again later
end
```

## Behaviour

- What `fn` answers (up to three values) is handed back. An **error** of `fn`
  is raised again as it was (no position added) after the lock is released.
- A holder that died leaves its file behind: a lock older than `opts.stale_s`
  (default 10 s; a locked write takes milliseconds) is taken over.
- Waiting is bounded by `opts.wait_ms` (default 2000), checked on every turn, so
  a stale lock that cannot be deleted does not spin the editor.
- A create that answers `EPERM`, `EACCES` or `EBUSY` is contention too (on
  Windows a lock unlinked a moment ago answers that until the delete completes).
  Any other error is a real failure.
- The lock file holds the pid of its holder.

## Failure: `nil, message, info`

`info.code` (the codes of
[`lib.nvim.contract.errors`](../../contract/errors/README.md)):

| `code` | Meaning | `retryable` |
|---|---|---|
| `locked` | another process holds it right now | `true` |
| `lock_stuck` | nobody will release it: older than the takeover age and not deletable, or a folder/link where the lock file should be. Remove it by hand. | `false` |
| `io` | the lock file could not be made (`cannot lock ...`) | `false` |

`info.lock` is the lock file, with forward slashes.

## Options

| | |
|---|---|
| `wait_ms` | Longest wait for a lock held by someone else (default 2000). |
| `stale_s` | Age in seconds after which a lock counts as left behind (default 10). |
| `create_exclusive` | Test seam: how the lock file is made (default `lib.nvim.fs.create_exclusive`). |
