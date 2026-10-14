# `lib.nvim.fs.create_exclusive`

Create a file with some content, **failing with `"exists"` when it is already
there**. The exclusive open (`O_CREAT|O_EXCL`) is the atomic part, so two
writers can never both believe they created the same file; a `lstat` first makes
a name that is taken by anything, a symlink included (dangling too), count as
`exists` (Windows' `O_EXCL` follows a dangling link and would create the file at
the link target, outside the folder). Moved here from
`tasks_nvim.fsio.create_exclusive` (tasks.nvim@921a0c4); it is the claim of a
new file and the lock file of [`lib.nvim.fs.with_lock`](../with_lock/README.md).

```lua
local create = require("lib.nvim.fs.create_exclusive")

local ok, err = create(dir .. "/new.md", "text")
if not ok and create.is_exists(err) then
  -- somebody else was first; the file is untouched
end
```

## Behaviour

- The parent directory is created first (`lib.nvim.fs.mkdirp`); a file where a
  folder should be is an error, not `exists`.
- Bytes are written as given: no newline is added, NUL and CRLF stay.
- An empty `content` makes an empty file.
- A folder with that name counts as present (`exists`). So does a symlink, a
  dangling one included, on every platform: nothing is created at its target and
  the link is left alone.
- A `path` that ends in a slash names a folder, not a file: `open failed: ...`,
  and no folder is made.
- A `path` or `content` that is not a string is answered as `invalid arguments`
  before anything is created (no empty file is left behind as a claim).
- A failed or short write removes the file again, so no half-written file is
  left that the next caller would read as `exists`.
- It never raises.

## API

The module is a callable table.

| | |
|---|---|
| `create(path, content)` | `true, nil`, or `false, err`. `err` is `"exists"` when the file was present, else `invalid arguments: ...` / `open failed: ...` / `write failed: ...`. |
| `create.EXISTS` | `"exists"`: the error for a file that was already there. |
| `create.is_exists(err)` | Whether `err` is `EXISTS`. Compare through this, not against the word. |
