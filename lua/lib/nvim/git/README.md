# `lib.nvim.git`

Small, composable Git query helpers for editor features (autocommands,
status integrations, conditional behavior). Every function shells out to the
`git` CLI via `lib.nvim.cross.run_argv` (argv form, no shell) and is
side-effect free; every function accepts an optional `git_cmd` to override
the `git` binary. `opts.dir` (see [below](#querying-a-different-repo-than-the-editors-cwd))
runs any of the cwd-implicit ones as `git -C <dir>`.

## Usage

```lua
local git = require("lib.nvim.git")

git.in_git_repo()          --> boolean
git.repo_root()            --> absolute path string, or nil
git.current_branch()       --> branch name, or nil in detached HEAD
git.is_detached_head()     --> boolean (false outside a repo: no HEAD to detach)
git.is_dirty()             --> boolean (any porcelain status output at all)
git.is_tracked("src/a.lua")  --> boolean
git.upstream()             --> "origin/main"-style string, or nil (no upstream)
git.head_hash()            --> full hash string, or nil
git.head_short_hash()      --> short hash string, or nil
git.describe()             --> nearest tag, or the short hash (--always), or nil
git.ahead_behind()         --> boolean ahead, boolean behind (vs. @{u})
```

All of these return `nil` (or `false`, for the boolean ones) rather than
throwing when the command fails or produces empty output — e.g. outside a
Git repo, `repo_root()`/`current_branch()`/etc. all just return `nil`.

`ahead_behind()` parses `git rev-list --left-right --count HEAD...@{u}`; if
the command fails, produces no output, or the output doesn't match
`"<n> <n>"`, both results are `false` rather than raising.

## Querying a different repo than the editor's cwd

Every function above reads the current working directory implicitly by
default — the right default for editor features, wrong for correlating data
with *a specific repo* (a plugin's own checkout, one row of a multi-repo
overview, the repo containing a given file). Pass `opts.dir` and the call runs
as `git -C <dir> ...` instead:

```lua
git.current_branch({ dir = "/path/to/some/plugin" })
git.status_porcelain({ dir = repo })
git.is_tracked("src/a.lua", { dir = repo })   -- path is relative to opts.dir
git.repo_root({ dir = "/repo/some/sub/dir" }) -- the root of *that* repo
```

`opts` comes **before** `git_cmd` in every signature (`is_tracked` takes its
`path` first). A nonexistent or non-repo `dir` behaves like any other
non-repo: `nil` / `false`, no error.

Passing a string where `opts` belongs — the old convention, where `git_cmd`
was the first parameter — **raises** instead of being ignored: silently
falling back to the default `git` would run a different binary than the one
the caller asked for.

`git.info(dir)` is the older, one-shot form of the same idea and keeps its
positional `dir`:

```lua
git.info("/path/to/some/plugin")
-- { branch = "main", version = "v1.2.3" or a short hash if untagged, commit = "abc1234" }
```

Runs `git -C <dir> ...` for each field; any field the command fails to
answer (detached HEAD for `branch`, no tags and no commits for `version`) is
`nil` rather than a guessed placeholder.

## Completing a revision argument

`git.refs(dir?, opts?)` lists the repository's named revisions — local
branches, then remote branches, then tags — for `<Tab>`-completing a "which
revision?" command argument.

```lua
git.refs()                                     -- cwd's repo, everything
git.refs("/path/to/repo", { limit = 20 })      -- another repo, capped
git.refs(nil, { remotes = false, tags = false })  -- local branches only
```

Two details matter more than they look:

- **Sorted by commit date, newest first.** `git for-each-ref` defaults to
  refname order, which puts whatever starts with `a` ahead of the branch you
  were on ten seconds ago. `-committerdate` puts the likely answer in the
  first few candidates.
- **Remote branches keep their prefix** (`origin/main`, not `main`), because
  that is how git itself accepts them as a revision. Stripping it would also
  collide with the identically named local branch.

Returns an empty list — never `nil` — for a non-repo, a nonexistent path, or
a repo with no commits, so a completion callback can return it directly.

## Status parsing

```lua
local status, err = git.status_porcelain({ dir = repo })   -- opts optional
-- table<string, { code: string, orig_path: string|nil }>, or nil, err

git.status_porcelain_async({ dir = repo }, function(status, err)
  -- runs on the main loop (vim.schedule): safe to touch buffers and windows
end)

git.parse_status(raw)   -- the pure parser, for a caller that runs git itself
```

Parses `git status --porcelain -z -u` into a path → status-code map. Handles
ordinary two-char XY codes (`M `, ` M`, `A `, `??`, `!!`, `UU`, …) as well as
rename/copy entries, which are keyed by the **new** path with `orig_path` set
to the old one; ordinary entries have `orig_path = nil`. Paths are always
relative to the **repository root**, whichever directory git was started in.

Ignored paths (`!!`) are **not** included unless `opts.ignored = true` adds
`--ignored` to the call — plain `-u` only controls untracked files, not
ignored ones.

A clean tree is `{}`; `nil` (plus an error string) means git itself failed —
not a repo, or `git` missing.

**Why `-z`.** Without it git C-quotes any path containing a space or a
non-ASCII byte: `a b.txt` arrives as `"a b.txt"` (quotes included) and `ü.txt`
as `"\303\274.txt"`, neither of which exists on disk. The NUL-separated form
delivers paths raw. In it a rename/copy is `XY new NUL old NUL` — destination
first — and an `R`/`C` in either status column marks such a two-path entry.

**Prefer `status_porcelain_async` on any automatic trigger** (a tree refresh on
every save or focus): the synchronous call freezes the UI for as long as
`git status` takes, which on a large tree is not nothing.

**Read-only by construction.** `status_porcelain`, its async twin and
`is_dirty` run `git --no-optional-locks status`. A plain `git status`
opportunistically refreshes — and rewrites — the index, taking `index.lock`
while it does; an automatic refresh that overlaps the user's own `git commit`
or `git add` would then make *that* command fail with "index.lock exists".
The trade-off is that stale stat data in the index is not repaired as a side
effect of these calls.

## Reading a file at a revision

```lua
local content, err = git.show("HEAD~1", "src/a.lua", { dir = repo })
git.show_async("v1.2.0", "assets/logo.png", { dir = repo }, function(blob, err) end)
```

`git show <rev>:<path>` with the content delivered **byte for byte**: a CRLF
file keeps its `\r\n`, a binary blob keeps every byte (including `NUL`), and an
empty file is `""` — deliberately not `nil`, which means *failure* here (unknown
revision, path not in that revision, not a repository), with the reason in the
second value. Text-mode handling of the output (what the other helpers here
use) would rewrite `\r\n` to `\n` and corrupt exactly the files a caller wants
to diff or hash, which is why this goes through `run_argv`'s `binary` option.

- `path` is relative to `opts.dir` (or the cwd), **not** to the repository
  root — the same meaning as in `blame_porcelain`/`is_tracked` — or absolute.
  An absolute path names its own directory, so `opts.dir` is ignored for it
  (and no extra process is needed to find the repository root).
- `rev` is anything `git show` resolves (`HEAD~1`, a branch, a tag, a hash),
  plus the index: `""` is the *staged* version (not the worktree), and during a
  merge conflict `":1"`, `":2"`, `":3"` are the base, ours and theirs versions.
- A `rev` that starts with `-` or contains a line break is **refused**
  (`nil, "…invalid revision…"`): it is glued to the front of one argument, and
  an option such as `--pretty=format:X` would make git succeed with output
  that is not the file.

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
