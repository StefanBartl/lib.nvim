# `lib.nvim.fs.with_lock`

Run a function while holding an **advisory lock** on a path: a hidden
`.<name>.lock` file next to it, created exclusively
([`create_exclusive`](../create_exclusive/README.md)). Every process that
read-modify-writes the same file (an agent's command line and an editor plugin)
goes through it, so two of them never start from the same text and drop each
other's change. It serialises the *cooperating* writers only; an editor with the
file open is not one of them. Moved here from `tasks_nvim.fsio.with_lock`
(tasks.nvim@6bc8d99).

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
- The takeover is **one waiter at a time**: it makes a transient sibling file
  `.<name>.lock.takeover` (exclusively, removed within microseconds) and reads
  the age of the lock again inside it, so a slow waiter never deletes the fresh
  lock another one has made meanwhile. A guard that a dying taker left behind is
  judged by the same rule (removed after `stale_s`). Processes that predate the
  guard (the original `tasks_nvim.fsio.with_lock`) ignore it and keep the old
  race among themselves.
- The release deletes the lock **only while it still holds the token of this
  call**. A holder that overran `stale_s` was taken over from; the file at the
  lock path is then its successor's and stays. That is a best-effort
  compare-then-delete (a window of microseconds remains), so keep `fn` well below
  `stale_s`. A lock that cannot be read is deleted as before.
- Waiting is bounded by `opts.wait_ms` (default 2000), checked on every turn, so
  a stale lock that cannot be deleted does not spin the editor.
- On **Windows**, a create that answers `EPERM`, `EACCES` or `EBUSY` is
  contention too (a lock unlinked a moment ago answers that until the delete
  completes). Elsewhere those words are a real refusal and fail at once as `io`.
  On Windows, if nothing occupies the lock path at the deadline although the
  create is still refused (a read-only folder, a denied ACL), the answer is `io`,
  not `locked`: asking again will not help. Any other error is a real failure.
- The lock file holds the pid of its holder on the first line and a token of
  this acquisition on the second.
- A link where the lock file should be (a dangling one included, on every
  platform) is `lock_stuck`; nothing is created at its target.
- A `path` that names no file (empty, or ending in a slash) is an `io` failure
  with `info.lock = ""`: no lock is made and no folder is created. (The original
  `tasks_nvim.fsio.with_lock` raised on it.) So is a `path` with a **NUL
  byte**: libuv cuts a path there, and the lock (and the caller's write) would be
  for another file.

## Limits

- **Keyed by the file the path resolves to** (`fs_realpath`): a symlink to the
  file, a symlinked folder (a junction), `.`/`..` segments and another case of
  an existing name on a case-insensitive disk all take the same lock, beside the
  real file. A **hard link** is a second name with nothing to resolve and takes
  another lock; a file that does not exist yet is keyed by its resolved folder
  and the name as spelled. The original `tasks_nvim.fsio.with_lock`
  (tasks.nvim@6bc8d99) keys by the spelling: switch all writers of a file at
  once.
- **Not re-entrant.** The lock is per path, not per caller: a nested `with_lock`
  on the same path from inside `fn` (a save hook that writes again) waits
  `wait_ms` and answers `locked`, even though the lock file holds your own pid.
  Do not nest; hand the already-locked work to the inner step.
- **The folder of the lock is created if missing** (`create_exclusive` makes the
  parent when the create answers `ENOENT`, so a contended retry costs no folder
  walk), and it stays: a mistyped folder name leaves a new empty folder
  behind. Check that the folder exists first if that matters.
- **It blocks the editor loop** (`vim.wait` in steps of 10 ms) while a lock is
  contended. For that reason a contended call cannot run in a fast-event context
  (a uv timer or another libuv callback): it raises `E5560` instead of answering
  `locked`. An uncontended call works there; wrap the call in `vim.schedule`
  when the context is unknown.

## Failure: `nil, message, info`

`info.code` (the codes of
[`lib.nvim.contract.errors`](../../contract/errors/README.md)):

| `code` | Meaning | `retryable` |
|---|---|---|
| `locked` | someone holds it right now (another process, or your own call further up the stack) | `true` |
| `lock_stuck` | nobody will release it: older than the takeover age and not deletable, or a folder/link where the lock file should be. Remove it by hand. | `false` |
| `io` | the lock file could not be made (`cannot lock ...`): a refusal no writer explains (read-only folder, denied ACL) among them, or `path` names no file | `false` |

`info.lock` is the lock file, with forward slashes (`""` when `path` names no
file).

## Options

| | |
|---|---|
| `wait_ms` | Longest wait for a lock held by someone else (default 2000). |
| `stale_s` | Age in seconds after which a lock counts as left behind (default 10). |
| `create_exclusive` | Test seam: how the lock file is made (default `lib.nvim.fs.create_exclusive`). It must write the given text as it is: the release looks for it. The takeover guard is always made by the real one. |
