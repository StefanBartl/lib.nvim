---@meta
---@module 'lib.nvim.git.@types'

---@class Lib.Git
---@field in_git_repo fun(git_cmd?: string): boolean # Check if current directory is inside a Git work-tree.
---@field repo_root fun(git_cmd?:string):string|nil # Get the absolute path to the repository root.
---@field current_branch fun(git_cmd?:string):string|nil # Get the current branch name. Returns nil in detached HEAD state.
---@field is_detached_head fun(git_cmd?:string):boolean # Check whether the repository is in a detached HEAD state.
---@field is_dirty fun(git_cmd?:string):boolean # Check whether the working tree has uncommitted changes.
---@field is_tracked fun(path:string, git_cmd?:string):boolean # Check whether the given path is tracked by Git.
---@field upstream fun(git_cmd?:string):string|nil # Get the upstream branch of the current branch.
---@field ahead_behind fun(git_cmd?:string):(boolean, boolean) # Check whether the current branch is ahead or behind its upstream.
---@field head_short_hash fun(git_cmd?:string):string|nil # Get the short hash of HEAD.
---@field info fun(dir: string, git_cmd?: string): { branch: string|nil, version: string|nil, commit: string|nil } # One-shot repo identity snapshot for an arbitrary directory (`git -C <dir> ...`), unlike every other function here which reads the cwd implicitly.
---@field refs fun(dir?: string, opts?: { branches?: boolean, remotes?: boolean, tags?: boolean, limit?: integer }, git_cmd?: string): string[] # Named revisions (local branches, remote branches, tags), each group most-recent-commit first, deduplicated. Built for <Tab>-completing a revision argument.
---@field status_porcelain fun(git_cmd?:string):table<string, { code: string, orig_path: string|nil }>|nil # Parse `git status --porcelain -u` into a path -> {code, orig_path} map. Renames/copies are keyed by their new path.
---@field remote_url fun(remote?: string, opts?: { dir?: string }, git_cmd?: string): string|nil # Get a configured remote's URL (defaults to "origin").
---@field relative_path fun(path: string, opts?: { dir?: string }, git_cmd?: string): string|nil # Resolve a tracked path's repository-relative form via `git ls-files --full-name`.
---@field current_ref fun(dir: string, git_cmd?: string): string|nil # The branch name, or (detached HEAD) the short commit hash, for an explicit directory. Two git calls, not three -- prefer this over `info(dir)` when the tag/version field isn't needed.
---@field blame_porcelain fun(path: string, opts?: { first?: integer, last?: integer, dir?: string }, git_cmd?: string): Lib.Git.BlameEntry[]|nil, string|nil # Blame a file (or a line range) via `git blame --porcelain`. nil only on a git-invocation failure -- an empty file is `{}`.
---@field blame_porcelain_async fun(path: string, opts: { first?: integer, last?: integer, dir?: string }|nil, on_done: fun(entries: Lib.Git.BlameEntry[]|nil, err: string|nil), git_cmd?: string): { stop: fun() } # Async counterpart to blame_porcelain -- prefer on a repeated/automatic trigger (e.g. CursorHold).
---@field clear_line_diff fun(ns:integer):fun(buf:integer):nil # Create a buffer-scoped function that clears all virtual text in the given namespace. This function binds the namespace once and returns a callback suitable for autocmd usage.

-- Lib.Git.BlameEntry is declared in git/init.lua, right above blame_porcelain
-- -- not duplicated here.

return {}
