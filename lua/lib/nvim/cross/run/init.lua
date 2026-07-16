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

--- Async run using vim.system when available; falls back to jobstart.
---@param cmd string
---@param cb fun(ok:boolean, res:OsRunResult)
---@return nil
function M.run(cmd, cb)
  local sh = M.shell()
  local function pack(code, signal, stdout, stderr)
    return { code = code or 0, signal = signal or 0, stdout = stdout or "", stderr = stderr or "" }
  end

  if vim.system then
    vim.system({ sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd }, { text = true }, function(obj)
      cb(obj.code == 0, pack(obj.code, obj.signal, obj.stdout, obj.stderr))
    end)
    return
  end

  -- Legacy fallback
  local full = sh.prog .. " " .. table.concat(sh.args, " ") .. " " .. cmd
  local stdout, stderr = {}, {}
  local jid = vim.fn.jobstart(full, {
    stdout_buffered = true,
    stderr_buffered = true,
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
---@return OsRunResult
function M.run_blocking(cmd)
  local sh = M.shell()
  if vim.system then
    local obj = vim.system({ sh.prog, sh.args[1], sh.args[2], sh.args[3], cmd }, { text = true }):wait()
    return { code = obj.code or 1, signal = obj.signal or 0, stdout = obj.stdout or "", stderr = obj.stderr or "" }
  end
  -- Minimal blocking fallback via systemlist()
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
