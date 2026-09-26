---@module 'lib.nvim.git'
--- Git utility helpers for Neovim.
---
--- This module provides small, composable helpers around common
--- Git queries that are frequently needed in editor features
--- (autocommands, status integrations, conditional behavior).
---
--- All functions are intentionally side-effect free and rely only
--- on invoking the Git CLI.
---
--- Every function that has no path of its own to act on takes an optional
--- `opts.dir` and then runs as `git -C <dir> ...` instead of against the
--- editor's cwd -- the right default for editor features, wrong for a caller
--- correlating data with a specific repo (a plugin's own checkout, one row of
--- a multi-repo overview, a file's containing repo).

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

---@internal
--- Build `{ bin, ["--no-optional-locks",] ["-C", dir,] ...args }`. An absent or
--- empty `opts.dir` leaves git to use the cwd.
---
--- `opts` must be a table (or nil). A string there is the pre-`opts.dir`
--- calling convention -- `git_cmd` used to be the first parameter -- and is
--- rejected loudly: quietly ignoring it would run the default `git` where the
--- caller asked for a specific binary.
---
--- `read_only` adds `--no-optional-locks` for a query that can refresh the
--- index (`status`): without it git opportunistically takes `index.lock`,
--- which makes a concurrent `git commit`/`git add` of the user fail with
--- "index.lock exists" whenever an automatic refresh happens to overlap it.
---@param bin string
---@param opts Lib.Git.Opts|nil
---@param args string[]
---@param read_only? boolean
---@return string[]
local function git_argv(bin, opts, args, read_only)
  if opts ~= nil and type(opts) ~= "table" then
    error(
      ("lib.nvim.git: `opts` must be a table like { dir = ... }, got %s -- `git_cmd` is now the last parameter"):format(
        type(opts)
      ),
      3
    )
  end
  local argv = { bin }
  if read_only then
    argv[#argv + 1] = "--no-optional-locks"
  end
  local dir = opts and opts.dir or nil
  if dir and dir ~= "" then
    argv[#argv + 1] = "-C"
    argv[#argv + 1] = dir
  end
  return vim.list_extend(argv, args)
end

-- =========================================================
-- Public API
-- =========================================================

--- Options shared by every function that can target a repo other than the cwd.
---@class Lib.Git.Opts
---@field dir? string Run as `git -C <dir>` instead of against the cwd.
---@field ignored? boolean Also list ignored paths (`git status --ignored`). Only honoured by `status_porcelain`/`status_porcelain_async`; every other function ignores it.

--- Check if the current working directory (or `opts.dir`) is inside a Git work-tree.
---@param opts? Lib.Git.Opts
---@param git_cmd? string Optional git binary (defaults to "git")
---@return boolean
function M.in_git_repo(opts, git_cmd)
  local out = git_system(git_argv(git_cmd or "git", opts, { "rev-parse", "--is-inside-work-tree" }))
  return out == "true"
end

--- Get the absolute path to the repository root.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.repo_root(opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "rev-parse", "--show-toplevel" }))
end

--- Get the current branch name.
--- Returns nil in detached HEAD state.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.current_branch(opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "symbolic-ref", "--short", "HEAD" }))
end

--- Check out an existing local branch or other revision (`git checkout
--- <name>`, a real filesystem/index mutation -- unlike every read-only
--- helper above).
---
--- Uses `run_blocking` (not `run_blocking_captured`, which the rest of this
--- module builds on): a failed checkout writes its reason to stderr, and
--- `run_blocking` is the one runner here that actually captures it (see its
--- own doc comment) -- a caller reporting a failed checkout to the user
--- needs git's real reason ("pathspec '<name>' did not match any file(s)
--- known to git", "Your local changes ... would be overwritten"), not the
--- read helpers' bare nil.
---
--- No `--` before `name`: that would tell `git checkout` to treat it as a
--- pathspec (restore a file from the index) instead of a branch -- exactly
--- the opposite of what this function does. A leading `-` is refused
--- outright instead, the same guard `show`'s `rev` argument uses.
---@param name string Branch name or other revision `git checkout` accepts. Must not start with `-`.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return boolean ok
---@return string|nil err Git's own stderr on failure, or the rejection reason for an invalid `name`.
function M.checkout(name, opts, git_cmd)
  if type(name) ~= "string" or name == "" or name:sub(1, 1) == "-" then
    return false, ("git checkout: invalid revision %s"):format(vim.inspect(name))
  end
  local argv = git_argv(git_cmd or "git", opts, { "checkout", name })
  return require("lib.nvim.cross.run_argv").run_blocking(argv)
end

--- Check whether the repository is in a detached HEAD state.
--- `false` outside a repository -- there is no HEAD to be detached.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return boolean
function M.is_detached_head(opts, git_cmd)
  local out = git_system(git_argv(git_cmd or "git", opts, { "symbolic-ref", "-q", "HEAD" }))
  if out ~= nil then
    return false
  end
  -- No output means either a detached HEAD or that the call failed outright
  -- (not a repo, git missing); `git_system` cannot tell the two apart, and a
  -- non-repo is not "detached".
  return M.in_git_repo(opts, git_cmd)
end

--- Check whether the working tree has uncommitted changes.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return boolean
function M.is_dirty(opts, git_cmd)
  local out = git_system(git_argv(git_cmd or "git", opts, { "status", "--porcelain" }, true))
  return out ~= nil
end

--- Check whether the given path is tracked by Git.
---@param path string Absolute path, or relative to `opts.dir`/the cwd.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return boolean
function M.is_tracked(path, opts, git_cmd)
  local out =
    git_system(git_argv(git_cmd or "git", opts, { "ls-files", "--error-unmatch", "--", path }))
  return out ~= nil
end

--- Get the upstream branch of the current branch.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.upstream(opts, git_cmd)
  return git_system(
    git_argv(
      git_cmd or "git",
      opts,
      { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }
    )
  )
end

--- Check whether the current branch is ahead or behind its upstream.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return boolean ahead, boolean behind
function M.ahead_behind(opts, git_cmd)
  local out = git_system(
    git_argv(git_cmd or "git", opts, { "rev-list", "--left-right", "--count", "HEAD...@{u}" })
  )
  if not out then
    return false, false
  end
  local left, right = out:match("^(%d+)%s+(%d+)$")
  if not left or not right then
    return false, false
  end
  return tonumber(left) > 0, tonumber(right) > 0
end

--- Get the full hash of HEAD.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.head_hash(opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "rev-parse", "HEAD" }))
end

--- Get the short hash of HEAD.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.head_short_hash(opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "rev-parse", "--short", "HEAD" }))
end

--- The nearest reachable tag (`git describe --tags`), or the short hash if
--- there is none yet (`--always`) -- "there is a version tag" and "there is
--- no tag" are both answered honestly, neither masquerading as the other.
--- Same command `M.info`'s `version` field runs, split out on its own for a
--- caller that wants only this and not `info`'s other two processes.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.describe(opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "describe", "--tags", "--always" }))
end

--- One-shot repo identity snapshot for an arbitrary directory. Takes an
--- explicit path (`git -C <dir> ...`) -- a caller correlating data with *a
--- specific plugin's* repo state (`lib.nvim.telemetry`'s `info` field, for
--- one) usually wants a different repo than whatever the editor's own cwd
--- happens to be. (It predates the `opts.dir` option the functions above now
--- share, hence its positional `dir`.)
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

--- One path's entry in a `status_porcelain` map.
---@class Lib.Git.StatusEntry
---@field code string          Two-character XY status (`" M"`, `"A "`, `"??"`, `"UU"`, ...)
---@field orig_path string|nil Source path of a rename/copy, nil for every other entry

--- Repo-root-relative path -> status entry. `git status --porcelain` never
--- honours `status.relativePaths`: paths are always relative to the repository
--- root, whatever directory git was started in.
---@alias Lib.Git.StatusMap table<string, Lib.Git.StatusEntry>

--- Parse `git status --porcelain -z -u` output into a path -> entry map.
---
--- Pure (no process), so it is headless-testable and reusable by a caller that
--- runs git itself. Takes the **NUL-separated** (`-z`) form: without `-z` git
--- C-quotes any path containing a space or a non-ASCII byte (`"a b.txt"`,
--- `"\303\274.txt"`), and undoing that is guesswork; with it, paths arrive raw.
---
--- Handles ordinary XY codes (M/A/D/R/C/U, "??" untracked, "!!" ignored) and
--- rename/copy entries. In `-z` form those are `XY new NUL old NUL` -- the
--- **destination first** -- and are keyed by the new path with the old one in
--- `orig_path`. An `R`/`C` in either column marks a two-path entry.
---@param raw string Output of `git status --porcelain -z`.
---@return Lib.Git.StatusMap
function M.parse_status(raw)
  local result = {} ---@type Lib.Git.StatusMap
  if type(raw) ~= "string" or raw == "" then
    return result
  end

  local fields = vim.split(raw, "\0", { plain = true })
  local i, n = 1, #fields
  while i <= n do
    local entry = fields[i]
    i = i + 1
    if #entry >= 4 and entry:sub(3, 3) == " " then
      local code, path = entry:sub(1, 2), entry:sub(4)
      local x, y = code:sub(1, 1), code:sub(2, 2)
      if x == "R" or x == "C" or y == "R" or y == "C" then
        local orig = fields[i]
        i = i + 1
        result[path] = { code = code, orig_path = (orig and orig ~= "") and orig or nil }
      else
        result[path] = { code = code, orig_path = nil }
      end
    end
  end
  return result
end

---@internal
---@param opts Lib.Git.Opts|nil
---@param bin string
---@return string[]
local function status_argv(opts, bin)
  local args = { "status", "--porcelain", "-z", "-u" }
  if opts and opts.ignored then
    args[#args + 1] = "--ignored"
  end
  return git_argv(bin, opts, args, true)
end

---@internal
---@param ok boolean
---@param out any
---@return Lib.Git.StatusMap|nil map
---@return string|nil err
local function status_result(ok, out)
  if not ok or type(out) ~= "string" then
    -- On a failed call `out` is usually empty (git writes its complaint to
    -- stderr), but a spawn failure (git not on $PATH) puts the reason there.
    return nil, (type(out) == "string" and vim.trim(out) ~= "") and out or "git status failed"
  end
  return M.parse_status(out), nil
end

--- The working tree's status as a path -> entry map (see `parse_status` for the
--- shape and the rename handling).
---
--- Synchronous: the underlying `run_blocking_captured` freezes the UI for the
--- call's duration, and `git status` on a large tree is not instant -- prefer
--- `status_porcelain_async` on any repeated or automatic trigger.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return Lib.Git.StatusMap|nil map  nil only on a git failure (not a repo, git missing); a clean tree is `{}`
---@return string|nil err
function M.status_porcelain(opts, git_cmd)
  local argv = status_argv(opts, git_cmd or "git")
  return status_result(require("lib.nvim.cross.run_argv").run_blocking_captured(argv))
end

--- Async counterpart to `status_porcelain` -- for a tree refresh that fires on
--- every save/focus, where a blocking call adds up.
---@param opts Lib.Git.Opts|nil
---@param on_done fun(map: Lib.Git.StatusMap|nil, err: string|nil) Always invoked via `vim.schedule` -- safe to touch buffers, windows and `vim.fn.*`.
---@param git_cmd? string
---@return { stop: fun() } handle Kills the underlying job; harmless to call after it has finished.
function M.status_porcelain_async(opts, on_done, git_cmd)
  local argv = status_argv(opts, git_cmd or "git")
  return require("lib.nvim.cross.run_argv").run_async_captured(argv, function(ok, out)
    on_done(status_result(ok, out))
  end)
end

--- Get a configured remote's URL.
---@param remote? string Remote name, defaults to "origin".
---@param opts? Lib.Git.Opts `dir` runs as `git -C <dir>` instead of the cwd.
---@param git_cmd? string
---@return string|nil
function M.remote_url(remote, opts, git_cmd)
  -- `--`: a remote name is caller data and must not be readable as an option.
  return git_system(
    git_argv(git_cmd or "git", opts, { "remote", "get-url", "--", remote or "origin" })
  )
end

--- Resolve a path's repository-relative form via `git ls-files --full-name`.
--- Only tracked files resolve (an untracked or ignored path returns nil) --
--- the intended use is "where does this file live inside the repo", and an
--- untracked file has no meaningful answer to that (it also cannot be
--- browsed on the remote, which is this function's original motivation).
---@param path string A basename (resolved relative to `opts.dir`) or an absolute path.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil
function M.relative_path(path, opts, git_cmd)
  return git_system(git_argv(git_cmd or "git", opts, { "ls-files", "--full-name", "--", path }))
end

--- The current ref for an explicit directory: the branch name, or (detached
--- HEAD) the short commit hash. Two git calls, not three -- prefer this over
--- `info(dir)` when the tag/version field isn't needed (e.g. deciding what
--- to link against for a browse URL), since `info` always pays for a third,
--- unused `git describe --tags --always` call on top.
---@param dir string
---@param git_cmd? string
---@return string|nil
function M.current_ref(dir, git_cmd)
  local bin = git_cmd or "git"
  local branch = git_system({ bin, "-C", dir, "symbolic-ref", "--short", "HEAD" })
  if branch then
    return branch
  end
  return git_system({ bin, "-C", dir, "rev-parse", "--short", "HEAD" })
end

---@internal
---@param path string
---@return boolean
local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

---@internal
--- Build the argv for `git show <rev>:./<path>`.
---
--- `./` makes git resolve `path` against `-C <dir>`/the cwd instead of the
--- repository root (the default of the bare `rev:path` form), so a relative
--- path means the same here as in `blame_porcelain` or `is_tracked`. An
--- absolute path names its own directory, which becomes `-C` -- no extra
--- process to find the repository root.
---
--- `rev` is caller data glued to the front of one argument, so a leading `-`
--- would make git read it as an option (`--output=<file>` writes a file):
--- refused here rather than escaped.
---@param rev string
---@param path string
---@param opts Lib.Git.Opts|nil
---@param bin string
---@return string[]|nil argv nil when the arguments are unusable.
---@return string what `<rev>:<path>` for messages, or the reason when argv is nil.
local function show_argv(rev, path, opts, bin)
  if type(rev) ~= "string" or rev:sub(1, 1) == "-" or rev:find("[%z\r\n]") then
    return nil, ("git show: invalid revision %s"):format(vim.inspect(rev))
  end
  if type(path) ~= "string" or path == "" then
    return nil, ("git show: invalid path %s"):format(vim.inspect(path))
  end

  local where, rel = opts, path
  if is_absolute(path) then
    where, rel = { dir = vim.fs.dirname(path) }, vim.fs.basename(path)
  elseif vim.fn.has("win32") == 1 then
    rel = (rel:gsub("\\", "/"))
  end
  return git_argv(bin, where, { "show", ("%s:./%s"):format(rev, rel) }), ("%s:%s"):format(rev, path)
end

---@internal
---@param ok boolean
---@param out any
---@param what string
---@return string|nil content
---@return string|nil err
local function show_result(ok, out, what)
  if not ok or type(out) ~= "string" then
    -- A failed `git show` writes nothing to stdout, so a non-empty `out` is a
    -- spawn failure's reason (git not on $PATH).
    if type(out) == "string" and out ~= "" then
      return nil, out
    end
    return nil,
      ("git show %s failed (unknown revision, path not in that revision, or not a repository)"):format(
        what
      )
  end
  return out, nil
end

--- The content of a file at a revision -- `git show <rev>:<path>` -- **byte for
--- byte**: a CRLF file keeps its `\r\n`, a binary blob keeps every byte
--- (including `NUL`). An empty file is `""`, which is why the result is not
--- collapsed to `nil` the way the other helpers here collapse empty output.
---
--- `path` is relative to `opts.dir`/the cwd (like `blame_porcelain`), or
--- absolute. `rev` is anything `git show` resolves -- `HEAD~1`, a branch, a tag,
--- a hash -- plus the index: `""` is the staged version and `":1"`/`":2"`/`":3"`
--- are the base/ours/theirs versions of a file in a merge conflict.
---
--- Synchronous (like most of this module); `show_async` for a repeated or
--- interactive trigger.
---@param rev string A revision, `""` for the index, or `":<stage>"`. Must not start with `-`.
---@param path string Relative to `opts.dir`/the cwd, or absolute.
---@param opts? Lib.Git.Opts
---@param git_cmd? string
---@return string|nil content nil on failure (unknown revision, path not in that revision, not a repo)
---@return string|nil err
function M.show(rev, path, opts, git_cmd)
  local argv, what = show_argv(rev, path, opts, git_cmd or "git")
  if not argv then
    return nil, what
  end
  local ok, out =
    require("lib.nvim.cross.run_argv").run_blocking_captured(argv, nil, { binary = true })
  return show_result(ok, out, what)
end

--- Async counterpart to `show`.
---@param rev string
---@param path string
---@param opts Lib.Git.Opts|nil
---@param on_done fun(content: string|nil, err: string|nil) Always invoked via `vim.schedule` -- safe to touch buffers, windows and `vim.fn.*`.
---@param git_cmd? string
---@return { stop: fun() } handle Kills the underlying job; harmless to call after it has finished.
function M.show_async(rev, path, opts, on_done, git_cmd)
  local argv, what = show_argv(rev, path, opts, git_cmd or "git")
  if not argv then
    vim.schedule(function()
      on_done(nil, what)
    end)
    return { stop = function() end }
  end
  return require("lib.nvim.cross.run_argv").run_async_captured(argv, function(ok, out)
    on_done(show_result(ok, out, what))
  end, nil, { binary = true })
end

--- One blamed line, as `blame_porcelain` returns it.
---@class Lib.Git.BlameEntry
---@field line integer          1-based final line number in the current file
---@field sha string            Full commit hash ("0000000000000000000000000000000000000000" for an uncommitted/working-tree line)
---@field author string|nil
---@field author_time integer|nil  Unix timestamp
---@field summary string|nil

---@internal
--- Parse `git blame --porcelain` output into one entry per line.
---
--- The porcelain format gives a full metadata block (author, author-time,
--- summary, ...) only the FIRST time a commit is mentioned; every later line
--- attributed to the same commit repeats just the header
--- (`<sha> <orig-line> <final-line>`) followed directly by the tab-prefixed
--- content line -- so metadata is cached per sha and reused for repeats,
--- rather than re-parsed or left nil.
---@param text string
---@return Lib.Git.BlameEntry[]
local function parse_blame_porcelain(text)
  local entries = {}
  local commits = {} ---@type table<string, { author: string|nil, author_time: integer|nil, summary: string|nil }>
  local lines = vim.split(text, "\n", { plain = true })
  local i, n = 1, #lines

  while i <= n do
    local line = lines[i]
    -- orig_line (the line number in the commit that introduced it) is
    -- unused here, so it is matched but not captured.
    local sha, final_line = line:match("^(%x+)%s+%d+%s+(%d+)")
    if not sha then
      i = i + 1
    else
      commits[sha] = commits[sha] or {}
      local c = commits[sha]
      i = i + 1
      while i <= n do
        local sub = lines[i]
        if sub:sub(1, 1) == "\t" then
          -- Content line: this entry is complete.
          entries[#entries + 1] = {
            line = tonumber(final_line),
            sha = sha,
            author = c.author,
            author_time = c.author_time,
            summary = c.summary,
          }
          i = i + 1
          break
        end
        local key, val = sub:match("^(%S+)%s(.*)$")
        if key == "author" then
          c.author = val
        elseif key == "author-time" then
          c.author_time = tonumber(val)
        elseif key == "summary" then
          c.summary = val
        end
        -- Every other porcelain key (author-mail, committer*, previous,
        -- filename, boundary, ...) is intentionally ignored: callers that
        -- need more than author/author-time/summary should parse the raw
        -- output themselves rather than growing this struct unboundedly.
        i = i + 1
      end
    end
  end

  return entries
end

---@internal
---@param path string
---@param opts { first?: integer, last?: integer, dir?: string }
---@param bin string
---@return string[]
local function blame_argv(path, opts, bin)
  local argv = { bin }
  if opts.dir and opts.dir ~= "" then
    vim.list_extend(argv, { "-C", opts.dir })
  end
  vim.list_extend(argv, { "blame", "--porcelain" })
  if opts.first and opts.last then
    argv[#argv + 1] = "-L"
    argv[#argv + 1] = ("%d,%d"):format(opts.first, opts.last)
  end
  vim.list_extend(argv, { "--", path })
  return argv
end

---@internal
---@param ok boolean
---@param out string
---@return Lib.Git.BlameEntry[]|nil entries
---@return string|nil err
local function blame_result(ok, out)
  if not ok then
    return nil, (type(out) == "string" and vim.trim(out) ~= "") and out or "git blame failed"
  end
  if type(out) ~= "string" or vim.trim(out) == "" then
    return {}, nil
  end
  return parse_blame_porcelain(out), nil
end

--- Blame a file (or a line range within it) via `git blame --porcelain`.
---
--- Synchronous, like every other function in this module (`ERR-01`: the
--- underlying `run_blocking_captured` call is a system-boundary shell-out,
--- and `git blame` on a large file can be slow -- prefer `blame_porcelain_async`
--- on a hot/repeated path, e.g. a `CursorHold`-driven refresh).
---@param path string File path, relative to `opts.dir`/the cwd, or absolute.
---@param opts? { first?: integer, last?: integer, dir?: string } `first`/`last` (both required together) restrict to a 1-based inclusive line range; `dir` runs as `git -C <dir>` instead of the cwd.
---@param git_cmd? string
---@return Lib.Git.BlameEntry[]|nil entries  nil only on a git-invocation failure (ERR-10/11: an empty file is `{}`, not nil)
---@return string|nil err
function M.blame_porcelain(path, opts, git_cmd)
  opts = opts or {}
  local argv = blame_argv(path, opts, git_cmd or "git")
  local ok, out = require("lib.nvim.cross.run_argv").run_blocking_captured(argv)
  return blame_result(ok, out)
end

--- Async counterpart to `blame_porcelain` -- LUA-15: prefer this over the
--- blocking version for any repeated/automatic trigger (a `CursorHold`-
--- driven current-line blame refresh, in particular), since
--- `run_blocking_captured` freezes the UI for the call's duration and a
--- refresh firing on every cursor move is exactly the repeated-blocking-call
--- pattern that adds up.
---@param path string File path, relative to `opts.dir`/the cwd, or absolute.
---@param opts? { first?: integer, last?: integer, dir?: string }
---@param on_done fun(entries: Lib.Git.BlameEntry[]|nil, err: string|nil)  Always invoked via `vim.schedule` (`run_async_captured`'s own guarantee) -- safe to touch buffers/windows/`vim.fn.*` from it.
---@param git_cmd? string
---@return { stop: fun() } handle  Kills the underlying job; harmless to call after it has already finished.
function M.blame_porcelain_async(path, opts, on_done, git_cmd)
  opts = opts or {}
  local argv = blame_argv(path, opts, git_cmd or "git")
  return require("lib.nvim.cross.run_argv").run_async_captured(argv, function(ok, out)
    on_done(blame_result(ok, out))
  end)
end

--- Fetch every remote's tracking refs and prune deleted ones
--- (`git fetch --all --prune`). Does not touch the working tree or `HEAD`.
---
--- Always async (`run_async_captured`, never a blocking counterpart): this is
--- a network call, and `lib.nvim.cross.run_argv`'s own reasoning for
--- `run_async_captured` -- "git over the network ... belongs here rather
--- than [blocking]" -- applies to every function in this section, not just
--- this one.
---
--- `changed` reports whether the fetch actually moved a remote-tracking ref:
--- git writes ref updates (`<old>..<new> main -> origin/main`) to stderr and
--- stays silent there when nothing was new. A failed fetch never reaches this
--- branch (`on_done` returns early on `ok == false`), so a present `changed`
--- always means the call actually succeeded.
---@param opts? Lib.Git.Opts
---@param on_done fun(ok: boolean, err: string|nil, changed: boolean|nil)
---@param git_cmd? string
---@return { stop: fun() } handle
function M.fetch_async(opts, on_done, git_cmd)
  local argv = git_argv(git_cmd or "git", opts, { "fetch", "--all", "--prune" })
  return require("lib.nvim.cross.run_argv").run_async_captured(
    argv,
    function(ok, _stdout, code, stderr)
      stderr = stderr or ""
      if not ok then
        on_done(
          false,
          (stderr ~= "" and stderr) or ("git fetch failed (exit code %d)"):format(code)
        )
        return
      end
      on_done(true, nil, stderr:match("%S") ~= nil)
    end
  )
end

--- Fast-forward-only pull of the current branch (`git pull --ff-only`).
--- Fails loudly (reported via `err`) rather than creating a merge commit --
--- the same "never clobber local work" guarantee `checkout` gives for
--- switching branches.
---
--- `changed` reports whether anything actually fast-forwarded: git prints
--- "Already up to date." to stdout when there was nothing to merge, and an
--- "Updating <old>..<new>"/"Fast-forward" summary otherwise.
---@param opts? Lib.Git.Opts
---@param on_done fun(ok: boolean, err: string|nil, changed: boolean|nil)
---@param git_cmd? string
---@return { stop: fun() } handle
function M.pull_async(opts, on_done, git_cmd)
  local argv = git_argv(git_cmd or "git", opts, { "pull", "--ff-only" })
  return require("lib.nvim.cross.run_argv").run_async_captured(
    argv,
    function(ok, stdout, code, stderr)
      if not ok then
        stderr = stderr or ""
        on_done(false, (stderr ~= "" and stderr) or ("git pull failed (exit code %d)"):format(code))
        return
      end
      on_done(true, nil, not (stdout or ""):lower():match("already up.to.date"))
    end
  )
end

--- Push the current branch to its upstream (`git push`).
---@param opts? Lib.Git.Opts
---@param on_done fun(ok: boolean, err: string|nil)
---@param git_cmd? string
---@return { stop: fun() } handle
function M.push_async(opts, on_done, git_cmd)
  local argv = git_argv(git_cmd or "git", opts, { "push" })
  return require("lib.nvim.cross.run_argv").run_async_captured(
    argv,
    function(ok, _stdout, code, stderr)
      if not ok then
        stderr = stderr or ""
        on_done(false, (stderr ~= "" and stderr) or ("git push failed (exit code %d)"):format(code))
        return
      end
      on_done(true, nil)
    end
  )
end

--- Fetch, then fast-forward pull -- the pair every "bring this repo level
--- with its upstream" caller wants (multi-repo dashboards, batch sync
--- tools), expressed once so they all agree on exactly what "update" means
--- instead of each spelling out the same two calls.
---
--- `changed` mirrors the pull's own -- that is what "did this checkout move
--- forward" means for the combined operation. A failed fetch short-circuits
--- before the pull ever runs.
---@param opts? Lib.Git.Opts
---@param on_done fun(ok: boolean, err: string|nil, changed: boolean|nil)
---@param git_cmd? string
---@return { stop: fun() } handle
function M.update_async(opts, on_done, git_cmd)
  return M.fetch_async(opts, function(ok, err)
    if not ok then
      on_done(false, err)
      return
    end
    M.pull_async(opts, on_done, git_cmd)
  end, git_cmd)
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

---@type Lib.Git
return M
