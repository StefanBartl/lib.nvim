---@module 'lib.nvim.git'
--- Git utility helpers for Neovim.
---
--- This module provides small, composable helpers around common
--- Git queries that are frequently needed in editor features
--- (autocommands, status integrations, conditional behavior).
---
--- All functions are intentionally side-effect free and rely only
--- on invoking the Git CLI.

local M = {}

-- =========================================================
-- Internal helpers
-- =========================================================

--- Execute a git command and return trimmed stdout.
--- Stderr is suppressed to avoid user-facing noise.
---@param cmd string
---@return string|nil
local function git_system(cmd)
  local out = vim.fn.system(cmd .. " 2>/dev/null")
  if type(out) ~= "string" then
    return nil
  end
  out = vim.trim(out)
  if out == "" then
    return nil
  end
  return out
end

-- =========================================================
-- Public API
-- =========================================================

--- Check if the current working directory is inside a Git work-tree.
---@param git_cmd? string Optional git binary (defaults to "git")
---@return boolean
function M.in_git_repo(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system(bin .. " rev-parse --is-inside-work-tree")
  return out == "true"
end

--- Get the absolute path to the repository root.
---@param git_cmd? string
---@return string|nil
function M.repo_root(git_cmd)
  local bin = git_cmd or "git"
  return git_system(bin .. " rev-parse --show-toplevel")
end

--- Get the current branch name.
--- Returns nil in detached HEAD state.
---@param git_cmd? string
---@return string|nil
function M.current_branch(git_cmd)
  local bin = git_cmd or "git"
  return git_system(bin .. " symbolic-ref --short HEAD")
end

--- Check whether the repository is in a detached HEAD state.
---@param git_cmd? string
---@return boolean
function M.is_detached_head(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system(bin .. " symbolic-ref -q HEAD")
  return out == nil
end

--- Check whether the working tree has uncommitted changes.
---@param git_cmd? string
---@return boolean
function M.is_dirty(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system(bin .. " status --porcelain")
  return out ~= nil
end

--- Check whether the given path is tracked by Git.
---@param path string Absolute or relative path
---@param git_cmd? string
---@return boolean
function M.is_tracked(path, git_cmd)
  local bin = git_cmd or "git"
  local out = git_system(bin .. " ls-files --error-unmatch " .. vim.fn.shellescape(path))
  return out ~= nil
end

--- Get the upstream branch of the current branch.
---@param git_cmd? string
---@return string|nil
function M.upstream(git_cmd)
  local bin = git_cmd or "git"
  return git_system(bin .. " rev-parse --abbrev-ref --symbolic-full-name @{u}")
end

--- Check whether the current branch is ahead or behind its upstream.
---@param git_cmd? string
---@return boolean ahead, boolean behind
function M.ahead_behind(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system(bin .. " rev-list --left-right --count HEAD...@{u}")
  if not out then
    return false, false
  end
  local left, right = out:match("^(%d+)%s+(%d+)$")
  if not left or not right then
    return false, false
  end
  return tonumber(left) > 0, tonumber(right) > 0
end

--- Get the short hash of HEAD.
---@param git_cmd? string
---@return string|nil
function M.head_short_hash(git_cmd)
  local bin = git_cmd or "git"
  return git_system(bin .. " rev-parse --short HEAD")
end

--- Create a buffer-scoped function that clears all virtual text
--- in the given namespace.
---
--- This function binds the namespace once and returns a callback
--- suitable for autocmd usage.
---@param ns integer Namespace ID created via nvim_create_namespace
---@return fun(buf: integer): nil
function M.clear_line_diff(ns)
  return function(buf)
    -- Ensure the buffer is still valid before mutating it
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
end

return M
