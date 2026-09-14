# `lib.nvim.checkpoint`

Snapshot a set of files before a destructive multi-file operation, so it
can be undone **byte-exact** if something goes wrong. For tools that
rewrite, move, or delete across a whole project (search-and-replace, a
bulk rename, an API migration) rather than a single buffer edit.

"Byte-exact" is the point of using `fs_copyfile` rather than reading lines
and writing them back: the latter can silently normalize line endings or
encoding on restore, which defeats the purpose of a backup.

Not transactional across a crash: backup files live under
`stdpath("cache")`, so they survive the current session but are not
fsync'd/journaled. This covers "the operation went wrong, undo it" (the
common case), not "Neovim was killed mid-write".

## Usage

```lua
local checkpoint = require("lib.nvim.checkpoint")

local cp, err = checkpoint.create({ "/proj/a.lua", "/proj/new.lua" })
if not cp then
  vim.notify(err)
  return
end

local ok = run_destructive_operation()
if ok then
  checkpoint.discard(cp)
else
  local restored, errors = checkpoint.restore(cp)
  checkpoint.discard(cp)
  if not restored then
    vim.notify("checkpoint restore had " .. #errors .. " failure(s)", vim.log.levels.ERROR)
  end
end
```

A path that does not exist yet at `create` time is still tracked — if the
guarded operation goes on to create it, `restore` deletes it, undoing the
creation along with everything else.

## API

| Function | Meaning |
| --- | --- |
| `checkpoint.create(paths, opts?)` | Snapshot every existing file in `paths`; returns `checkpoint\|nil, err` |
| `checkpoint.restore(checkpoint)` | Copy every backed-up file back verbatim, delete any file that didn't exist before; returns `ok, errors[]` (best-effort — one failure doesn't stop the rest) |
| `checkpoint.discard(checkpoint)` | Delete the checkpoint's backup directory; call once the guarded operation succeeded or was already restored |

`opts` for `create`:

| Field | Default | Meaning |
| --- | --- | --- |
| `dir` | `stdpath("cache") .. "/lib.nvim/checkpoints"` | Override the checkpoint root |

## Semantics worth knowing

- **File copies, not diffs.** Every existing tracked file gets a full
  `fs_copyfile` backup, not a delta — simple and byte-exact, at the cost of
  disk space proportional to the tracked files' total size.
- **Restore is best-effort.** A locked or since-deleted file failing to
  restore does not stop the rest of the checkpoint from being applied;
  check the returned `errors` list.
- **Built on `lib.nvim.cross.fs.mutate`**, so copy/delete operations get
  the same Windows sharing-violation retry behavior as the rest of the
  library.
