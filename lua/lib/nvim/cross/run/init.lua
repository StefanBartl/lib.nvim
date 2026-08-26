---@module 'lib.nvim.cross.run'
-- Shell selection and runners

-- FIX: Optimize, doc

local M = {}

--- Pick a shell suitable for the platform.
---@return OsShell
function M.shell()
  if require("lib").is_windows() and not require("lib").is_wsl() then
    return {
      prog = "powershell",
      args = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command" },
      is_powershell = true,
    }
  end
  return { prog = "sh", args = { "-lc" }, is_powershell = false }
end

---@internal
--- Resolve the `env` table to hand `vim.system`/`jobstart`. By default every
--- `run`/`run_blocking` call is enriched via `cross.run.env.build()` — a
--- guaranteed-complete `PATH` plus recoverable session/keyring variables —
--- so callers get that fix without doing anything (see
--- `docs/guides/subprocess-env.md`). `opts.env = false` opts a call back
--- out entirely, reverting to bare `vim.system`/`jobstart` inheritance (the
--- pre-existing behaviour); `opts.env` as a table is folded in as overrides
--- on top of the built environment, same precedence as `env.apply()`.
---@param opts Lib.Cross.Run.RunOpts
---@return table<string,string>|nil
local function resolve_env(opts)
  if opts.env == false then
    return nil
  end

  local build_opts = opts.env_opts or {}
  if type(opts.env) == "table" then
    build_opts = vim.tbl_extend(
      "force",
      build_opts,
      { vars = vim.tbl_extend("force", opts.env, build_opts.vars or {}) }
    )
  end

  return require("lib.nvim.cross.run.env").build(build_opts)
end

--- Async run using vim.system when available; falls back to jobstart.
---@param cmd string
---@param cb fun(ok:boolean, res:OsRunResult)
---@param opts? Lib.Cross.Run.RunOpts
---@return nil
function M.run(cmd, cb, opts)
  opts = opts or {}
  local sh = M.shell()
  local env = resolve_env(opts)
  local function pack(code, signal, stdout, stderr)
    return { code = code or 0, signal = signal or 0, stdout = stdout or "", stderr = stderr or "" }
  end

  if vim.system then
    vim.system(
      { sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd },
      { text = true, env = env },
      function(obj)
        cb(obj.code == 0, pack(obj.code, obj.signal, obj.stdout, obj.stderr))
      end
    )
    return
  end

  -- Legacy fallback
  local full = sh.prog .. " " .. table.concat(sh.args, " ") .. " " .. cmd
  local stdout, stderr = {}, {}
  local jid = vim.fn.jobstart(full, {
    stdout_buffered = true,
    stderr_buffered = true,
    env = env,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, code, signal)
      cb(code == 0, pack(code, signal, table.concat(stdout, "\n"), table.concat(stderr, "\n")))
    end,
  })
  if jid <= 0 then
    cb(false, pack(1, 0, "", "jobstart failed"))
  end
end

--- Blocking run (utility for quick conversions / probing).
---@param cmd string
---@param opts? Lib.Cross.Run.RunOpts
---@return OsRunResult
function M.run_blocking(cmd, opts)
  opts = opts or {}
  local sh = M.shell()
  local env = resolve_env(opts)
  if vim.system then
    local obj = vim
      .system({ sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd }, { text = true, env = env })
      :wait()
    return {
      code = obj.code or 1,
      signal = obj.signal or 0,
      stdout = obj.stdout or "",
      stderr = obj.stderr or "",
    }
  end
  -- Minimal blocking fallback via systemlist(). systemlist() has no env
  -- parameter of its own; a caller relying on `opts.env`/enrichment here
  -- degrades silently to bare process inheritance on this legacy path.
  local full = sh.prog .. " " .. table.concat(sh.args, " ") .. " " .. cmd
  local ok, out = pcall(vim.fn.systemlist, full)
  local code = vim.v.shell_error or 1
  return {
    code = code,
    signal = 0,
    stdout = ok and table.concat(out, "\n") or "",
    stderr = ok and "" or "systemlist failed",
  }
end

--- Launch `argv` detached from Neovim (fire-and-forget, no output capture).
--- On Windows/WSL, GUI processes (e.g. `explorer.exe`, `notepad`) are launched
--- via `jobstart(..., { detach = true })` instead of `vim.system`, because
--- `vim.system`'s process detachment is unreliable for GUI processes on
--- those platforms — `jobstart` with `detach = true` handles it correctly.
--- Elsewhere, `vim.system(argv, { detach = true })` is used when available.
---
--- GUI processes only, on Windows. libuv's DETACHED_PROCESS leaves the child
--- without standard handles, and a CONSOLE program launched this way exits
--- before running anything: a detached `powershell.exe -Command Set-Content …`
--- returns a valid job id and never writes the file. A GUI process does not
--- care, which is why `explorer.exe` works here and PowerShell does not. For a
--- console helper, spawn it normally (`vim.system(argv, {})`) and simply don't
--- wait on it — see `lib.nvim.cross.reveal_in_fm`, which needs both.
---@param argv string[]
---@return boolean ok
---@return string|nil err
function M.run_detached(argv)
  if type(argv) ~= "table" or not argv[1] then
    return false, "argv must be a non-empty string list"
  end

  local is_windows = require("lib.nvim.cross.platform.is_windows")()
  local is_wsl = require("lib.nvim.cross.platform.is_wsl")()

  if is_windows or is_wsl then
    local jid = vim.fn.jobstart(argv, { detach = true })
    if jid <= 0 then
      return false, "jobstart failed"
    end
    return true, nil
  end

  if vim.system then
    local ok, err = pcall(vim.system, argv, { detach = true })
    if not ok then
      return false, tostring(err)
    end
    return true, nil
  end

  local jid = vim.fn.jobstart(argv, { detach = true })
  if jid <= 0 then
    return false, "jobstart failed"
  end
  return true, nil
end

return M
