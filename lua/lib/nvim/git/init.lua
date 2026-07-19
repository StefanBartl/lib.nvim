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

--- Execute a git command (argv, no shell) and return trimmed stdout.
--- Stderr is suppressed to avoid user-facing noise.
---@param argv string[]
---@return string|nil
local function git_system(argv)
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(argv)
  if not ok or type(out) ~= "string" then
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
  local out = git_system({ bin, "rev-parse", "--is-inside-work-tree" })
  return out == "true"
end

--- Get the absolute path to the repository root.
---@param git_cmd? string
---@return string|nil
function M.repo_root(git_cmd)
  local bin = git_cmd or "git"
  return git_system({ bin, "rev-parse", "--show-toplevel" })
end

--- Get the current branch name.
--- Returns nil in detached HEAD state.
---@param git_cmd? string
---@return string|nil
function M.current_branch(git_cmd)
  local bin = git_cmd or "git"
  return git_system({ bin, "symbolic-ref", "--short", "HEAD" })
end

--- Check whether the repository is in a detached HEAD state.
---@param git_cmd? string
---@return boolean
function M.is_detached_head(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system({ bin, "symbolic-ref", "-q", "HEAD" })
  return out == nil
end

--- Check whether the working tree has uncommitted changes.
---@param git_cmd? string
---@return boolean
function M.is_dirty(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system({ bin, "status", "--porcelain" })
  return out ~= nil
end

--- Check whether the given path is tracked by Git.
---@param path string Absolute or relative path
---@param git_cmd? string
---@return boolean
function M.is_tracked(path, git_cmd)
  local bin = git_cmd or "git"
  local out = git_system({ bin, "ls-files", "--error-unmatch", path })
  return out ~= nil
end

--- Get the upstream branch of the current branch.
---@param git_cmd? string
---@return string|nil
function M.upstream(git_cmd)
  local bin = git_cmd or "git"
  return git_system({ bin, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
end

--- Check whether the current branch is ahead or behind its upstream.
---@param git_cmd? string
---@return boolean ahead, boolean behind
function M.ahead_behind(git_cmd)
  local bin = git_cmd or "git"
  local out = git_system({ bin, "rev-list", "--left-right", "--count", "HEAD...@{u}" })
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
  return git_system({ bin, "rev-parse", "--short", "HEAD" })
end

--- Parse `git status --porcelain -u` output into a path -> status-code map.
--- Handles ordinary XY codes (M/A/D/R/C/U, "??" untracked, "!!" ignored) and
--- rename/copy entries ("R  old -> new" / "C  old -> new"), keying renames
--- by their *new* path while recording the old path alongside the code.
---@param git_cmd? string
---@return table<string, { code: string, orig_path: string|nil }>|nil
function M.status_porcelain(git_cmd)
  local bin = git_cmd or "git"
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured({ bin, "status", "--porcelain", "-u" })
  if type(out) ~= "string" then
    return nil
  end
  if not ok and out == "" then
    return nil
  end

  local result = {} ---@type table<string, { code: string, orig_path: string|nil }>
  for line in out:gmatch("[^\r\n]+") do
    local code, rest = line:sub(1, 2), line:sub(4)
    if code ~= "" and rest ~= "" then
      local orig_path, new_path = rest:match("^(.-)%s*%->%s*(.+)$")
      if orig_path and new_path then
        result[new_path] = { code = code, orig_path = orig_path }
      else
        result[rest] = { code = code, orig_path = nil }
      end
    end
  end
  return result
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
