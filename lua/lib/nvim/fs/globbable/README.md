# `lib.nvim.fs.globbable`

A spelling of a directory path that is safe to hand to `vim.fn.glob` /
`vim.fn.globpath`.

```lua
local globbable = require("lib.nvim.fs.globbable")

local files = vim.fn.globpath(globbable(root), "**/*.lua", false, true)
```

## The problem

`glob` and `globpath` read their argument as a **pattern**, not as a path, and
a `~` in a pattern is a home-directory reference.

On Windows that makes an 8.3 short name fatal. `%TEMP%`, `vim.fn.tempname()`
and any `getcwd()` inherited from one of them come back as
`C:/Users/STEFAN~1/...` whenever the profile name is longer than eight
characters. Glob then tries to resolve `~1` as a user, finds no such user, and
returns an **empty list** — no error, no warning. Code that globs a directory
it was handed reports "nothing here" for a directory full of files.

This is not hypothetical. It was found in production in two backends that
searched a temp directory and concluded it was empty: `filetree.nvim`'s
`find_files` builtin backend and `pdfport.nvim`'s marker backend. Verified
directly: the same tree globs to 2 entries under the long path and 0 under
`C:/Users/STEFAN~1/...`.

## The fix

`uv.fs_realpath` gives back the long form, which globs correctly.

- A root with no `~` in it is returned untouched — no syscall. That is the
  common case, and this sits directly in front of directory scans.
- A root that does not exist is returned unchanged: glob would find nothing
  under it either way.
- A non-string or empty input returns `""`.

## When to reach for `normkey` instead

[`normkey`](../normkey/README.md) is for *comparing* paths — a canonical key
for caches and dedup, which also resolves symlinks, uppercases the drive
letter and collapses separators. Use it wherever two paths must be recognized
as the same path.

`globbable` is for *handing a path to glob*. It does the minimum needed for
that one job and leaves the spelling alone otherwise, because glob's caller
generally wants the results to come back looking like the root it passed in.

## Known gap: the other metacharacters

A directory whose **name** contains `[`, `]`, `*` or `?` is the same class of
hazard — glob will read those as pattern syntax too. This module does not
handle them, deliberately:

- `fs_realpath` cannot help; the characters are really in the name.
- Escaping is not portable. The backslash is the escape character for glob and
  the path separator on Windows, so the escaped form is ambiguous exactly
  where it would be needed.

If a caller must be robust against arbitrary directory names, the answer is
not a glob at all but `uv.fs_scandir` / `lib.nvim.fs.collect_recursive`, which
take a path as a path.
