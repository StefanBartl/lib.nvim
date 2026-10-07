-- TESTS/git_fixture.lua — throwaway git repositories for the git specs.
--
-- Not a spec (TESTS/run.lua does not list it): a spec loads it with
--
--   local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
--   local F = dofile(dir .. "git_fixture.lua")(H)
--
-- and calls `F.cleanup()` when it is done. Real repositories, never string
-- mocks: what these specs pin is git's actual output.

return function(H)
  local F = {}
  local created = {} ---@type string[]

  -- Identity and config pinned on the command line so a runner's global git
  -- config (a signing key, autocrlf, a default branch) cannot change a result.
  local BASE = {
    "git",
    "-c",
    "user.name=lib-nvim-spec",
    "-c",
    "user.email=spec@example.invalid",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "tag.gpgsign=false",
    "-c",
    "core.autocrlf=false",
    "-c",
    "protocol.file.allow=always",
  }

  ---@param suffix? string
  ---@return string dir
  function F.tmpdir(suffix)
    local dir = vim.fn.tempname() .. (suffix or "")
    vim.fn.mkdir(dir, "p")
    created[#created + 1] = dir
    return dir
  end

  --- Run git in `dir`. A step that fails is a spec failure, never a silent
  --- skip, unless the caller asks for `allow_fail`.
  ---@param dir string
  ---@param args string[]
  ---@param opts? { env?: table<string, string>, allow_fail?: boolean }
  ---@return string stdout trimmed
  ---@return integer code
  ---@return string stderr
  function F.git(dir, args, opts)
    opts = opts or {}
    local argv = vim.list_extend(vim.deepcopy(BASE), { "-C", dir })
    vim.list_extend(argv, args)
    local res = vim.system(argv, { text = true, env = opts.env }):wait()
    if not opts.allow_fail then
      H.ok(
        res.code == 0,
        ("fixture: git %s failed (%d): %s"):format(table.concat(args, " "), res.code, res.stderr)
      )
    end
    return vim.trim(res.stdout or ""), res.code, res.stderr or ""
  end

  --- Write `text` to `path` byte for byte, creating the directory.
  ---@param path string
  ---@param text string
  function F.write(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
  end

  --- The environment that pins a commit's author and committer date.
  ---@param epoch integer
  ---@return table<string, string>
  function F.when(epoch)
    local stamp = ("%d +0000"):format(epoch)
    return { GIT_AUTHOR_DATE = stamp, GIT_COMMITTER_DATE = stamp }
  end

  --- A new repository on branch `main`.
  ---@param suffix? string
  ---@return string dir
  function F.init(suffix)
    local dir = F.tmpdir(suffix)
    F.git(dir, { "init", "-q", "-b", "main" })
    return dir
  end

  --- Stage everything and commit with `message` **verbatim** (`-F`, no
  --- cleanup: CRLF and control bytes survive). An empty commit is allowed.
  ---@param dir string
  ---@param message string
  ---@param opts? { when?: integer, author_when?: integer } Committer time (and, unless given, author time).
  ---@return string sha
  function F.commit(dir, message, opts)
    opts = opts or {}
    local env = F.when(opts.when or 1700000000)
    if opts.author_when then
      env.GIT_AUTHOR_DATE = ("%d +0000"):format(opts.author_when)
    end
    local msg_file = vim.fn.tempname()
    F.write(msg_file, message)
    F.git(dir, { "add", "-A" })
    F.git(
      dir,
      { "commit", "-q", "--allow-empty", "--cleanup=verbatim", "-F", msg_file },
      { env = env }
    )
    vim.fn.delete(msg_file)
    local sha = F.git(dir, { "rev-parse", "HEAD" })
    return sha
  end

  function F.cleanup()
    for _, dir in ipairs(created) do
      vim.fn.delete(dir, "rf")
    end
    created = {}
  end

  return F
end
