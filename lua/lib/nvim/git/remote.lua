---@module 'lib.nvim.git.remote'
--- Remote-URL parsing and web-URL building for the three hosted Git forges
--- (GitHub, GitLab, Codeberg) plus self-hosted instances a caller declares.
--- Pure: no `vim.api`, no process, headless-testable -- moved here from
--- gitsuite.nvim's `features/browse/url.lua` (GS-16) once a second and
--- third consumer (github_stats.nvim, documentation.nvim) needed the same
--- grammar instead of each parsing remotes with their own regex.

local M = {}

---Parse a git remote URL into {host, owner, repo}. Supports
---`https://[user@]host/owner/repo(.git)?`, `git@host:owner/repo(.git)?`,
---and `ssh://[user@]host/owner/repo(.git)?`.
---@param url string
---@return { host: string, owner: string, repo: string }|nil
function M.parse_remote(url)
  local host, rest = url:match("^https?://[^/@]+@([^/]+)/(.+)$")
  if not host then
    host, rest = url:match("^https?://([^/]+)/(.+)$")
  end
  if not host then
    host, rest = url:match("^git@([^:]+):(.+)$")
  end
  if not host then
    host, rest = url:match("^ssh://[^/@]+@([^/]+)/(.+)$")
  end
  if not host or not rest then
    return nil
  end

  rest = rest:gsub("%.git/?$", "")
  local owner, repo = rest:match("^(.-)/([^/]+)$")
  if not owner or not repo then
    return nil
  end
  return { host = host, owner = owner, repo = repo }
end

---Classify a remote host. `github.com`/`gitlab.com`/`codeberg.org` are
---built in; anything else is looked up in `hosts_cfg` (a caller-supplied
---map, e.g. gitsuite.nvim's `cfg.browse.hosts`).
---@param host string
---@param hosts_cfg table<string, "github"|"gitlab"|"codeberg">
---@return "github"|"gitlab"|"codeberg"|nil
function M.host_kind(host, hosts_cfg)
  if host == "github.com" then
    return "github"
  end
  if host == "gitlab.com" then
    return "gitlab"
  end
  if host == "codeberg.org" then
    return "codeberg"
  end
  return hosts_cfg[host]
end

---Build a web URL for a file (optionally with a line anchor) or, with
---`rel_path == nil`, the repository root. `rel_path`/`branch` are expected
---to be git-controlled values, never raw user text, but this still only
---ever produces an http(s) URL string -- nothing is shelled out from here.
---@param kind "github"|"gitlab"|"codeberg"
---@param remote { host: string, owner: string, repo: string }
---@param branch string
---@param rel_path string|nil
---@param first integer|nil
---@param last integer|nil
---@return string
function M.build(kind, remote, branch, rel_path, first, last)
  local base = ("https://%s/%s/%s"):format(remote.host, remote.owner, remote.repo)
  if not rel_path then
    return base
  end

  local anchor = ""
  if first then
    anchor = (last and last ~= first) and ("#L%d-L%d"):format(first, last) or ("#L%d"):format(first)
  end

  if kind == "gitlab" then
    return ("%s/-/blob/%s/%s%s"):format(base, branch, rel_path, anchor)
  elseif kind == "codeberg" then
    -- Also the shape most self-hosted Gitea/Forgejo forks accept.
    return ("%s/src/branch/%s/%s%s"):format(base, branch, rel_path, anchor)
  end
  return ("%s/blob/%s/%s%s"):format(base, branch, rel_path, anchor)
end

return M
