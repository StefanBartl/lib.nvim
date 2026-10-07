---@module 'lib.nvim.git.remote'
--- Remote-URL parsing and web-URL building for the three hosted Git forges
--- (GitHub, GitLab, Codeberg) plus self-hosted instances a caller declares.
--- Pure: no `vim.api`, no process, headless-testable -- moved here from
--- gitsuite.nvim's `features/browse/url.lua` (GS-16) once a second and
--- third consumer (github_stats.nvim, documentation.nvim) needed the same
--- grammar instead of each parsing remotes with their own regex.

local encoding = require("lib.lua.strings.encoding")

local M = {}

---@internal
--- Percent-encode a path for use inside a URL path, segment by segment --
--- `/` itself is preserved as the separator (encoding it too would turn a
--- real subdirectory, or a branch name that legitimately contains one, into
--- a literal `%2F` and break the link instead of fixing it). Reviewed after
--- `M.build` shipped interpolating `branch`/`rel_path` raw: a tracked file
--- or branch name containing `#`/`?`/a space is common enough (POSIX
--- filesystems allow all three) and would otherwise truncate the URL at a
--- `#` (read as the fragment separator) or `?` (read as the query
--- separator) instead of naming the file.
---@param path string
---@return string
local function encode_path(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    parts[#parts + 1] = encoding.url_encode(part)
  end
  return table.concat(parts, "/")
end

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
---map, e.g. gitsuite.nvim's `cfg.browse.hosts`). Without a map only the
---three built-in hosts are known -- `nil`, not an error, for any other.
---@param host string
---@param hosts_cfg? table<string, "github"|"gitlab"|"codeberg">
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
  return hosts_cfg and hosts_cfg[host] or nil
end

---Build a web URL for a file (optionally with a line anchor) or, with
---`rel_path == nil`, the repository root. `branch`/`rel_path` are expected
---to be git-controlled values, never raw user text, but a tracked file or
---branch name can still legitimately contain a space, `#` or `?` (any of
---which would otherwise truncate or misdirect the URL) -- both are
---percent-encoded segment by segment before going into the path, `/`
---itself preserved as the separator. Nothing is shelled out from here.
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

  local enc_branch, enc_path = encode_path(branch), encode_path(rel_path)
  if kind == "gitlab" then
    return ("%s/-/blob/%s/%s%s"):format(base, enc_branch, enc_path, anchor)
  elseif kind == "codeberg" then
    -- Also the shape most self-hosted Gitea/Forgejo forks accept.
    return ("%s/src/branch/%s/%s%s"):format(base, enc_branch, enc_path, anchor)
  end
  return ("%s/blob/%s/%s%s"):format(base, enc_branch, enc_path, anchor)
end

---@internal
---@param remote { host: string, owner: string, repo: string }
---@return string
local function repo_base(remote)
  return ("https://%s/%s/%s"):format(remote.host, remote.owner, remote.repo)
end

---Web URL of one commit. GitLab keeps its `/-/` namespace; GitHub, Codeberg
---and the Gitea/Forgejo forks that share Codeberg's shape use `/commit/`.
---`sha` is anything the host resolves (a full or abbreviated hash, a branch
---or tag name); it is percent-encoded like every other path part.
---@param kind "github"|"gitlab"|"codeberg"
---@param remote { host: string, owner: string, repo: string }
---@param sha string
---@return string
function M.commit_url(kind, remote, sha)
  local seg = encode_path(sha)
  if kind == "gitlab" then
    return ("%s/-/commit/%s"):format(repo_base(remote), seg)
  end
  return ("%s/commit/%s"):format(repo_base(remote), seg)
end

---Web URL comparing two revisions: what `head` has that `base` lacks. The
---three-dot form (`base...head`, the merge-base based diff) is the one every
---host accepts as the web page of a comparison.
---@param kind "github"|"gitlab"|"codeberg"
---@param remote { host: string, owner: string, repo: string }
---@param base string
---@param head string
---@return string
function M.compare_url(kind, remote, base, head)
  local range = ("%s...%s"):format(encode_path(base), encode_path(head))
  if kind == "gitlab" then
    return ("%s/-/compare/%s"):format(repo_base(remote), range)
  end
  return ("%s/compare/%s"):format(repo_base(remote), range)
end

---Web URL of a tag: the release page on GitHub/Codeberg (which also exists
---for a tag without release notes), the tag page on GitLab.
---@param kind "github"|"gitlab"|"codeberg"
---@param remote { host: string, owner: string, repo: string }
---@param tag string
---@return string
function M.tag_url(kind, remote, tag)
  local seg = encode_path(tag)
  if kind == "gitlab" then
    return ("%s/-/tags/%s"):format(repo_base(remote), seg)
  end
  return ("%s/releases/tag/%s"):format(repo_base(remote), seg)
end

return M
