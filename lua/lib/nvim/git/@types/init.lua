---@meta
---@module 'lib.nvim.git.@types'

---@class Lib.Git
---@field in_git_repo fun(opts?: Lib.Git.Opts, git_cmd?: string): boolean # Check if the cwd (or `opts.dir`) is inside a Git work-tree.
---@field repo_root fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get the absolute path to the repository root.
---@field current_branch fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get the current branch name. Returns nil in detached HEAD state.
---@field is_detached_head fun(opts?: Lib.Git.Opts, git_cmd?: string): boolean # Check whether the repository is in a detached HEAD state.
---@field is_dirty fun(opts?: Lib.Git.Opts, git_cmd?: string): boolean # Check whether the working tree has uncommitted changes.
---@field is_tracked fun(path: string, opts?: Lib.Git.Opts, git_cmd?: string): boolean # Check whether the given path is tracked by Git.
---@field upstream fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get the upstream branch of the current branch.
---@field ahead_behind fun(opts?: Lib.Git.Opts, git_cmd?: string): (boolean, boolean) # Check whether the current branch is ahead or behind its upstream.
---@field head_hash fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get the full hash of HEAD.
---@field head_short_hash fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get the short hash of HEAD.
---@field describe fun(opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Nearest reachable tag (`git describe --tags`), or the short hash if there is none (`--always`).
---@field info fun(dir: string, git_cmd?: string): { branch: string|nil, version: string|nil, commit: string|nil } # One-shot repo identity snapshot for an arbitrary directory (`git -C <dir> ...`).
---@field refs fun(dir?: string, opts?: { branches?: boolean, remotes?: boolean, tags?: boolean, limit?: integer }, git_cmd?: string): string[] # Named revisions (local branches, remote branches, tags), each group most-recent-commit first, deduplicated. Built for <Tab>-completing a revision argument.
---@field parse_status fun(raw: string): Lib.Git.StatusMap # Pure parser for `git status --porcelain -z` output (path -> {code, orig_path}); renames/copies are keyed by their new path.
---@field status_porcelain fun(opts?: Lib.Git.Opts, git_cmd?: string): Lib.Git.StatusMap|nil, string|nil # Working-tree status as a path -> {code, orig_path} map (`-z`, so paths with spaces/non-ASCII are exact). nil + err only on a git failure; a clean tree is `{}`.
---@field status_porcelain_async fun(opts: Lib.Git.Opts|nil, on_done: fun(map: Lib.Git.StatusMap|nil, err: string|nil), git_cmd?: string): { stop: fun() } # Async counterpart to status_porcelain -- prefer on a repeated/automatic trigger.
---@field remote_url fun(remote?: string, opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Get a configured remote's URL (defaults to "origin").
---@field relative_path fun(path: string, opts?: Lib.Git.Opts, git_cmd?: string): string|nil # Resolve a tracked path's repository-relative form via `git ls-files --full-name`.
---@field current_ref fun(dir: string, git_cmd?: string): string|nil # The branch name, or (detached HEAD) the short commit hash, for an explicit directory. Two git calls, not three -- prefer this over `info(dir)` when the tag/version field isn't needed.
---@field show fun(rev: string, path: string, opts?: Lib.Git.Opts, git_cmd?: string): string|nil, string|nil # A file's content at a revision (`git show <rev>:<path>`), byte for byte (CRLF and binary intact); an empty file is `""`. `rev` may be `""` (the index) or `":1"`/`":2"`/`":3"` (merge stages). nil + err on failure.
---@field show_async fun(rev: string, path: string, opts: Lib.Git.Opts|nil, on_done: fun(content: string|nil, err: string|nil), git_cmd?: string): { stop: fun() } # Async counterpart to show.
---@field blame_porcelain fun(path: string, opts?: { first?: integer, last?: integer, dir?: string }, git_cmd?: string): Lib.Git.BlameEntry[]|nil, string|nil # Blame a file (or a line range) via `git blame --porcelain`. nil only on a git-invocation failure -- an empty file is `{}`.
---@field blame_porcelain_async fun(path: string, opts: { first?: integer, last?: integer, dir?: string }|nil, on_done: fun(entries: Lib.Git.BlameEntry[]|nil, err: string|nil), git_cmd?: string): { stop: fun() } # Async counterpart to blame_porcelain -- prefer on a repeated/automatic trigger (e.g. CursorHold).
---@field clear_line_diff fun(ns:integer):fun(buf:integer):nil # Create a buffer-scoped function that clears all virtual text in the given namespace. This function binds the namespace once and returns a callback suitable for autocmd usage.

-- Lib.Git.Opts, Lib.Git.StatusEntry/StatusMap and Lib.Git.BlameEntry are
-- declared in git/init.lua, right above the functions that use them -- not
-- duplicated here.

return {}
