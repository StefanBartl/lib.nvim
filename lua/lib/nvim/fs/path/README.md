# `lib.nvim.fs.path`

Small grab-bag of path helpers that don't warrant their own module. For a
chainable, `plenary.Path`-style OOP wrapper, see
[`lib.nvim.fs.path.object`](#libnvimfspathobject) below — additive,
not a replacement for the flat API on this page.

## Usage

```lua
local path = require("lib.nvim.fs.path")

path.from_repo_relative("src/a.lua")   --> absolute path, resolved below
path.joinpath({ "a", "b", "c.lua" })   --> "a/b/c.lua" (native separator if vim.fs.joinpath is unavailable)
path.ensure_dir("/tmp/logs/out.log")   --> true  (creates /tmp/logs if missing; the file itself is untouched)
```

### `from_repo_relative(raw)`

Resolves a path that may be relative to a repository root (as returned by
tools like LazyGit, which hand back forward-slash, repo-root-relative paths)
to an absolute one. If `raw` is already absolute (Windows drive, UNC, or
POSIX root), it's returned normalized (`vim.fn.fnamemodify(raw, ":p")`) as-is.
Otherwise it tries, in order: `raw` joined onto the Git root of the current
working directory (via `lib.nvim.git`'s `repo_root()`), then `raw` resolved
against the cwd directly — the first candidate that is `filereadable` wins;
if neither is readable, the last candidate (the cwd-relative one) is returned
anyway.

### `joinpath(parts)`

Thin wrapper around `vim.fs.joinpath`, with a manual `table.concat` fallback
(using `package.config`'s platform separator) for the rare case it's
unavailable.

### `ensure_dir(path)`

Ensures the *parent directory* of a file `path` exists, creating it (and any
missing ancestors) via [`lib.nvim.fs.mkdirp`](../mkdirp/README.md) if needed.
Deliberately fast-event safe: unlike the `vim.fn.mkdir`/`fnamemodify`-based
approach it replaced, this only touches `vim.fs.dirname` (pure Lua) and
`mkdirp` (libuv-only), so it can be called from a `uv` timer, an `fs_event`
watcher, or a subprocess stdout callback — exactly where a log sink needs it,
and exactly where the old implementation aborted with `E5560: Vimscript
function must not be called in a fast event context`. Returns `true`
immediately if `path` has no parent directory (empty, `"."`, or the parent
already exists); returns `false, "empty path"` if `path` itself is empty/nil.

## `lib.nvim.fs.path.object`

A chainable OOP `Path`, built on [`lib.lua.class`](../../../lua/class/README.md).
Every method is a thin facade over an existing `lib.nvim.fs` primitive —
none of the filesystem logic here is new.

```lua
local Path = require("lib.nvim.fs.path.object")

local p = Path.new("/tmp/report.txt")
p:write("hello\n")
p:exists()          --> true
p:is_dir()           --> false
p:read()             --> "hello\n"
p:joinpath("sibling") --> a new Path("/tmp/report.txt/sibling")
p:parent()            --> a new Path("/tmp")
p:iter()              --> string[]: every path recursively under this one
```

| Method               | Delegates to                                      |
|-----------------------|-----------------------------------------------------|
| `Path.new(path)`       | —                                                    |
| `:exists()`            | `(vim.uv or vim.loop).fs_stat`                       |
| `:is_dir()`            | `(vim.uv or vim.loop).fs_stat`                       |
| `:read()`              | `lib.nvim.fs.read`                                   |
| `:write(content)`      | `lib.nvim.fs.write.to_file`                          |
| `:joinpath(...)`       | `lib.nvim.fs.path.joinpath` — returns a new `Path`   |
| `:parent()`            | `vim.fs.dirname` — returns a new `Path`              |
| `:iter(opts?)`         | `lib.nvim.fs.collect_recursive.collect`              |

`:iter()` is a **full recursive walk**, not plenary's shallow
`Path:iter()` — `collect_recursive` has no depth limit to opt out of.
