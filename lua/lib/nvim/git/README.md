# `lib.nvim.git`

Small, composable Git query helpers for editor features (autocommands,
status integrations, conditional behavior). Every function shells out to the
`git` CLI via `lib.nvim.cross.run_argv` (argv form, no shell) and is
side-effect free; every function accepts an optional `git_cmd` to override
the `git` binary.

## Usage

```lua
local git = require("lib.nvim.git")

git.in_git_repo()          --> boolean
git.repo_root()            --> absolute path string, or nil
git.current_branch()       --> branch name, or nil in detached HEAD
git.is_detached_head()     --> boolean
git.is_dirty()             --> boolean (any porcelain status output at all)
git.is_tracked("src/a.lua")  --> boolean
git.upstream()             --> "origin/main"-style string, or nil (no upstream)
git.head_short_hash()      --> short hash string, or nil
git.ahead_behind()         --> boolean ahead, boolean behind (vs. @{u})
```

All of these return `nil` (or `false`, for the boolean ones) rather than
throwing when the command fails or produces empty output — e.g. outside a
Git repo, `repo_root()`/`current_branch()`/etc. all just return `nil`.

`ahead_behind()` parses `git rev-list --left-right --count HEAD...@{u}`; if
the command fails, produces no output, or the output doesn't match
`"<n> <n>"`, both results are `false` rather than raising.

## Querying a different repo than the editor's cwd

Every function above reads the current working directory implicitly — the
right default for editor features, wrong for correlating data with *a
specific plugin's* repo state (e.g. `lib.nvim.telemetry`'s `info` field,
tagging a report with the branch/version of the plugin it was collected
from, not of whatever the editor's cwd happens to be).

```lua
git.info("/path/to/some/plugin")
-- { branch = "main", version = "v1.2.3" or a short hash if untagged, commit = "abc1234" }
```

Runs `git -C <dir> ...` for each field; any field the command fails to
answer (detached HEAD for `branch`, no tags and no commits for `version`) is
`nil` rather than a guessed placeholder.

## Status parsing

```lua
local status = git.status_porcelain()
-- table<string, { code: string, orig_path: string|nil }>, or nil
```

Parses `git status --porcelain -u` into a path → status-code map. Handles
ordinary two-char XY codes (`M `, ` M`, `A `, `??`, `!!`, …) as well as
rename/copy entries (`R  old -> new`, `C  old -> new`), which are keyed by
the **new** path with `orig_path` set to the old one; ordinary entries have
`orig_path = nil`.

## Diagnostics cleanup helper

```lua
local ns = vim.api.nvim_create_namespace("my-plugin-diff")
local clear = git.clear_line_diff(ns)   -- binds ns once

vim.api.nvim_create_autocmd("BufLeave", {
  callback = function(args) clear(args.buf) end,
})
```

`clear_line_diff(ns)` returns a `fun(buf: integer)` closure that clears all
virtual text in namespace `ns` for a given buffer — guards against an invalid
buffer (already wiped) before calling `nvim_buf_clear_namespace`.
