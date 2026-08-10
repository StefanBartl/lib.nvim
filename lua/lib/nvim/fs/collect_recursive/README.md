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

-- Non-blocking counterpart, same options, for large trees (node_modules-
-- sized) where the synchronous walk above would stall the main loop:
local cancel = collect_recursive.collect_async("/repo", { kind = "files" }, function(paths)
  -- called once, vim.schedule-dispatched, never for a cancelled walk
end)
-- cancel()  -- stop early if the caller no longer needs the result
```

## Returns

| Function             | Returns    | Meaning                                             |
|-----------------------|------------|------------------------------------------------------|
| `M.collect(root, opts)` | `string[]` | Absolute paths matching `opts.kind` (default `"all"`) |
| `M.files(root, opts)`   | `string[]` | Shorthand for `collect` with `kind = "files"`         |
| `M.dirs(root, opts)`    | `string[]` | Shorthand for `collect` with `kind = "dirs"`          |

When `opts.ignore(abs_path, is_dir)` returns `true` for a directory, that
directory entry is skipped **and** its subtree is not recursed into.

## `collect_async(root, opts, on_done)`

Non-blocking counterpart to `collect`, same result and same `opts` (`kind`,
`ignore`). `walk`'s synchronous `uv.fs_scandir`/`uv.fs_stat` calls block the
caller until the syscall returns — fine for a handful of directories, but a
`node_modules`-sized tree stalls Neovim's UI for the whole walk.
`collect_async` uses the async form of those same libuv calls instead, one
directory at a time, driven by a small internal coroutine (`await`/
`run_async`) so the recursive walk still reads like the synchronous version
— no callback pyramid — while every `await()` actually yields control back
to the event loop.

This fixes the main-loop stall; it is **not** a parallel/concurrent scan and
so not necessarily a wall-clock speedup — sibling directories are still
visited one after another, deliberately, to keep the coroutine driver
simple. `M.files_async`/`M.dirs_async` mirror `files`/`dirs`.

```
M.collect_async(root: string, opts?: Lib.Fs.CollectRecursive.Opts, on_done: fun(paths: string[])): fun() cancel
M.files_async(root: string, opts?: Lib.Fs.CollectRecursive.Opts, on_done: fun(paths: string[])): fun() cancel
M.dirs_async(root: string, opts?: Lib.Fs.CollectRecursive.Opts, on_done: fun(paths: string[])): fun() cancel
```

`on_done` is always `vim.schedule`-dispatched and fires **at most once**;
calling the returned `cancel()` function stops the walk after its current
in-flight libuv call settles and `on_done` is not called at all — not
"called with a partial result", genuinely skipped.
