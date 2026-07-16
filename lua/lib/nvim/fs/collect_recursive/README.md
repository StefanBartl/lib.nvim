# `lib.nvim.fs.collect_recursive`

Recursive directory walker built on `(vim.uv or vim.loop).fs_scandir`/
`fs_scandir_next`. Returns a flat array of absolute paths under a root
directory, with an optional `ignore` predicate that can prune whole
subtrees — pass a matcher once instead of every consumer hand-rolling its
own recursive scan (Neo-tree-style pickers, project indexers, …).

## Usage

```lua
local collect_recursive = require("lib.nvim.fs.collect_recursive")

-- Everything (files + directories)
local all = collect_recursive.collect("/repo")

-- Files only, skipping .git and node_modules subtrees entirely
local files = collect_recursive.files("/repo", {
  ignore = function(abs_path, is_dir)
    return is_dir and (abs_path:match("/%.git$") ~= nil or abs_path:match("/node_modules$") ~= nil)
  end,
})

-- Directories only
local dirs = collect_recursive.dirs("/repo")
```

## Returns

| Function             | Returns    | Meaning                                             |
|-----------------------|------------|------------------------------------------------------|
| `M.collect(root, opts)` | `string[]` | Absolute paths matching `opts.kind` (default `"all"`) |
| `M.files(root, opts)`   | `string[]` | Shorthand for `collect` with `kind = "files"`         |
| `M.dirs(root, opts)`    | `string[]` | Shorthand for `collect` with `kind = "dirs"`          |

When `opts.ignore(abs_path, is_dir)` returns `true` for a directory, that
directory entry is skipped **and** its subtree is not recursed into.
