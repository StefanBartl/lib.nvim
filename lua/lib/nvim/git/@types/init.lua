---@meta
---@module 'lib.nvim.git.@types'

---@class Lib.Git
---@field in_git_repo fun(git_cmd: string): boolean # Check if current directory is inside a Git work-tree.
---@field repo_root fun(git_cmd?:string):string|nil # Get the absolute path to the repository root.
---@field current_branch fun(git_cmd?:string):string|nil # Get the current branch name. Returns nil in detached HEAD state.
---@field is_detached_head fun(git_cmd?:string):boolean # Check whether the repository is in a detached HEAD state.
---@field is_dirty fun(git_cmd?:string):boolean # Check whether the working tree has uncommitted changes.
---@field is_tracked fun(path:string, git_cmd?:string):boolean # Check whether the given path is tracked by Git.
---@field upstream fun(git_cmd?:string):string|nil # Get the upstream branch of the current branch.
---@field ahead_behind fun(git_cmd?:string):(boolean, boolean) # Check whether the current branch is ahead or behind its upstream.
---@field head_short_hash fun(git_cmd?:string):string|nil # Get the short hash of HEAD.
---@field clear_line_diff fun(ns:integer):fun(buf:integer):nil # Create a buffer-scoped function that clears all virtual text in the given namespace. This function binds the namespace once and returns a callback suitable for autocmd usage.

return {}
