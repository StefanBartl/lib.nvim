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

---@internal
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

--- One-shot repo identity snapshot for an arbitrary directory. Unlike every
--- other function here, which reads the current working directory
--- implicitly, this takes an explicit path (`git -C <dir> ...`) — a caller
--- correlating data with *a specific plugin's* repo state (`lib.nvim.
--- telemetry`'s `info` field, for one) usually wants a different repo than
--- whatever the editor's own cwd happens to be, not this one extended with
--- a `cwd` parameter on every existing function above.
---@param dir string Absolute or relative path inside the target repo.
---@param git_cmd? string
---@return { branch: string|nil, version: string|nil, commit: string|nil }
function M.info(dir, git_cmd)
  local bin = git_cmd or "git"
  ---@internal
  local function run(args)
    local argv = { bin, "-C", dir }
    for _, a in ipairs(args) do
      argv[#argv + 1] = a
    end
    return git_system(argv)
  end
  return {
    -- `nil` in detached HEAD, same as `current_branch` above.
    branch = run({ "symbolic-ref", "--short", "HEAD" }),
    -- The nearest reachable tag, or the short hash if none exists yet
    -- (`--always`) — "version tag" and "there is no tag" both answered
    -- honestly rather than one masquerading as the other.
    version = run({ "describe", "--tags", "--always" }),
    commit = run({ "rev-parse", "--short", "HEAD" }),
  }
end

--- List the repository's named revisions: local branches, then remote
--- branches, then tags — each group sorted by most recent commit first, and
--- the whole list deduplicated in that order.
---
--- Built for `<Tab>` completion of a "which revision?" argument, which is why
--- the ordering matters more than it looks: `git for-each-ref` defaults to
--- refname order, so a plain listing puts whatever starts with "a" in front
--- of the branch you were on ten seconds ago. `-committerdate` puts the
--- answer the user most likely wants within the first few candidates.
---
--- Remote branches are offered with their remote prefix (`origin/main`) and
--- local ones without, because that is exactly how git itself accepts them
--- as a revision — no normalization, so every candidate is directly usable.
---
--- Takes an explicit `dir` for the same reason `info` above does: a caller
--- completing a revision for *a particular repository* usually does not mean
--- the editor's cwd.
---@param dir? string Path inside the target repo. Defaults to the cwd.
---@param opts? { branches?: boolean, remotes?: boolean, tags?: boolean, limit?: integer } Which groups to include (all three default to true) and a cap on the total.
---@param git_cmd? string
---@return string[] # Possibly empty — a fresh repo with no commits has no refs, and neither does a non-repo.
function M.refs(dir, opts, git_cmd)
  opts = opts or {}
  local bin = git_cmd or "git"

  ---@param pattern string
  ---@param strip integer How many leading ref path components to drop.
  ---@return string[]
  local function for_each_ref(pattern, strip)
    local argv = { bin }
    if dir and dir ~= "" then
      argv[#argv + 1] = "-C"
      argv[#argv + 1] = dir
    end
    vim.list_extend(argv, {
      "for-each-ref",
      "--sort=-committerdate",
      ("--format=%%(refname:strip=%d)"):format(strip),
      pattern,
    })
    local out = git_system(argv)
    if not out then
      return {}
    end
    return vim.split(out, "\n", { trimempty = true })
  end

  local groups = {}
  if opts.branches ~= false then
    groups[#groups + 1] = for_each_ref("refs/heads/", 2)
  end
  if opts.remotes ~= false then
    -- strip=2 leaves "origin/main", which is what git accepts as a revision;
    -- strip=3 would leave a bare "main" that collides with the local branch.
    groups[#groups + 1] = for_each_ref("refs/remotes/", 2)
  end
  if opts.tags ~= false then
    groups[#groups + 1] = for_each_ref("refs/tags/", 2)
  end

  local out, seen = {}, {}
  for _, group in ipairs(groups) do
    for _, ref in ipairs(group) do
      if not seen[ref] then
        seen[ref] = true
        out[#out + 1] = ref
        if opts.limit and #out >= opts.limit then
          return out
        end
      end
    end
  end
  return out
end

--- Parse `git status --porcelain -u` output into a path -> status-code map.
--- Handles ordinary XY codes (M/A/D/R/C/U, "??" untracked, "!!" ignored) and
--- rename/copy entries ("R  old -> new" / "C  old -> new"), keying renames
--- by their *new* path while recording the old path alongside the code.
---@param git_cmd? string
---@return table<string, { code: string, orig_path: string|nil }>|nil
function M.status_porcelain(git_cmd)
  local bin = git_cmd or "git"
  local ok, out =
    require("lib.nvim.cross.run_argv").run_blocking_captured({ bin, "status", "--porcelain", "-u" })
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
