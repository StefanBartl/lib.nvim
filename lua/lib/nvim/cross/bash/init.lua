---@module 'lib.nvim.cross.bash'
--- Locate the bash that runs `.sh` scripts: Git Bash on Windows, `bash` elsewhere.
---
--- On Windows the `bash` on PATH is often `C:\Windows\System32\bash.exe` (or
--- the `WindowsApps` alias), the WSL launcher: it starts a Linux distribution,
--- cannot read Windows script paths and fails without one installed. A caller
--- that wants to run `scripts/ci.sh` needs Git Bash. Candidates, in order:
---
---   1. `$ProgramFiles/Git/bin/bash.exe`, `$ProgramW6432/Git/bin/bash.exe` (a 32-bit
---      process sees the x86 folder in the first), `C:/Program Files/Git/bin/bash.exe`
---   2. beside the `git.exe` on PATH (`<root>/cmd`, `<root>/bin`, `<root>/mingw64/bin`
---      -> `<root>/bin/bash.exe`): portable and custom installs, no process
---   3. derived from `git --exec-path` (`<root>/<mingw64|clangarm64|...>/libexec/git-core`
---      -> `<root>/bin/bash.exe`; a scoop shim): one process
---   4. `bash` on PATH: an absolute `.exe` that is not in the current directory and not
---      the WSL launcher (checked on its real path too, so an 8.3 name does not hide it)
---
--- Only `<root>/bin/bash.exe` is taken: Git for Windows' wrapper that puts `usr/bin` (sed,
--- grep, ...) on PATH. A bare `usr/bin/bash.exe` (MSYS2) runs scripts without coreutils
--- unless `usr/bin` is on PATH already, and then tier 4 finds it.
---
--- Elsewhere the answer is the absolute path of `bash` on PATH.
---
--- The result (also a miss) is memoized; `clear()` drops it. `locate(io)` is the
--- pure lookup with every system access injected (specs fake it).

local executable = require("lib.nvim.cross.executable")

local M = {}

---@class Lib.Cross.Bash.Io
---@field is_windows fun(): boolean
---@field getenv fun(name: string): string|nil
---@field is_file fun(path: string): boolean
---@field git_exec_path fun(): string|nil  `git --exec-path`, nil when git is missing or fails
---@field exepath fun(name: string): string|nil  PATH lookup, nil when not found
---@field realpath? fun(path: string): string|nil  resolve 8.3 names and links (the launcher check)
---@field cwd? fun(): string  the current directory (a `bash.exe` there is never taken)

---@param path string
---@return string
local function slashes(path)
  return (path:gsub("\\", "/"))
end

--- Whether `path` is the WSL launcher (System32 or a WindowsApps alias), never Git Bash.
---@param path string
---@return boolean
function M.is_wsl_launcher(path)
  local p = slashes(path):lower()
  return p:find("/system32/", 1, true) ~= nil
    or p:find("/sysnative/", 1, true) ~= nil
    or p:find("/windowsapps/", 1, true) ~= nil
end

---@param exec_path string  output of `git --exec-path`
---@return string|nil root  the install root (`<root>/<mingw64|clangarm64|ucrt64|...>/libexec/git-core`)
local function git_root(exec_path)
  local p = slashes(vim.trim(exec_path)):gsub("/+$", "")
  return p:match("^(%a:.-)/[%w_]+/libexec/git%-core$")
end

--- Pure lookup. Returns the bash path, or nil and the reason (naming every place searched).
---@param io Lib.Cross.Bash.Io
---@return string|nil path
---@return string|nil reason
function M.locate(io)
  local realpath = io.realpath or function(p)
    return p
  end
  if not io.is_windows() then
    -- the absolute path: a bare name is looked up again at spawn time, where an empty PATH entry is `./`
    local p = io.exepath("bash")
    if p and p:sub(1, 1) == "/" then
      return p
    end
    return nil, "bash is not on PATH"
  end

  local tried, seen = {}, {}
  ---@param candidate string|nil
  ---@return string|nil
  local function try(candidate)
    if not candidate or candidate == "" then
      return nil
    end
    candidate = slashes(candidate)
    -- In a 64-bit process ProgramFiles and ProgramW6432 are the same folder as the fixed default.
    local key = candidate:lower()
    if seen[key] then
      return nil
    end
    seen[key] = true
    tried[#tried + 1] = candidate
    if
      io.is_file(candidate) and not M.is_wsl_launcher(slashes(realpath(candidate) or candidate))
    then
      return candidate
    end
    return nil
  end

  -- 1. the installer's places and the fixed default: one stat each, no process
  for _, var in ipairs({ "ProgramFiles", "ProgramW6432" }) do
    local base = io.getenv(var)
    local hit = base and base ~= "" and try(slashes(base):gsub("/+$", "") .. "/Git/bin/bash.exe")
    if hit then
      return hit
    end
  end
  local hit = try("C:/Program Files/Git/bin/bash.exe")
  if hit then
    return hit
  end

  -- 2. beside the git on PATH (`<root>/cmd/git.exe`, `<root>/bin/git.exe`, `<root>/mingw64/bin/git.exe`):
  -- portable and custom installs, still without starting a process
  local git = io.exepath("git")
  local git_dir = git and slashes(git):match("^(%a:/.+)/[^/]+$")
  local root = git_dir
    and (
      git_dir:match("^(.+)/cmd$")
      or git_dir:match("^(.+)/[%w_]+/bin$")
      or git_dir:match("^(.+)/bin$")
    )
  hit = root and try(root .. "/bin/bash.exe")
  if hit then
    return hit
  end

  -- 3. `git --exec-path` (a scoop shim on PATH points nowhere useful): one process
  local exec_path = io.git_exec_path()
  root = exec_path and git_root(exec_path)
  hit = root and try(root .. "/bin/bash.exe")
  if hit then
    return hit
  end

  -- 4. `bash` on PATH: only an absolute `.exe` (a `.bat`/`.cmd` would run through cmd.exe, whose
  -- quoting libuv does not do), not in the current directory, never the WSL launcher
  local on_path = io.exepath("bash")
  if on_path then
    local p = slashes(on_path)
    local cwd = io.cwd and io.cwd()
    local dir = p:match("^(.+)/[^/]+$")
    if M.is_wsl_launcher(slashes(realpath(p) or p)) then
      tried[#tried + 1] = p .. " (WSL launcher, skipped)"
    elseif not p:lower():match("%.exe$") or not p:match("^%a:/") then
      tried[#tried + 1] = p .. " (not an absolute .exe, skipped)"
    elseif cwd and dir and dir:lower() == slashes(cwd):gsub("/+$", ""):lower() then
      tried[#tried + 1] = p .. " (in the current directory, skipped)"
    else
      hit = try(p)
      if hit then
        return hit
      end
    end
  end

  return nil,
    "Git Bash not found; searched: " .. (#tried > 0 and table.concat(tried, ", ") or "nothing")
end

---@type Lib.Cross.Bash.Io
local system_io = {
  is_windows = require("lib.nvim.cross.platform.is_windows"),
  getenv = function(name)
    return (vim.uv or vim.loop).os_getenv(name)
  end,
  is_file = function(path)
    local st = (vim.uv or vim.loop).fs_stat(path)
    return st ~= nil and st.type == "file"
  end,
  realpath = function(path)
    return (vim.uv or vim.loop).fs_realpath(path)
  end,
  cwd = function()
    return (vim.uv or vim.loop).cwd()
  end,
  git_exec_path = function()
    if not executable.exists("git") then
      return nil
    end
    local ok, res = pcall(function()
      return vim.system({ "git", "--exec-path" }, { text = true }):wait(5000)
    end)
    if not ok or not res or res.code ~= 0 then
      return nil
    end
    return res.stdout
  end,
  exepath = function(name)
    return executable.path(name)
  end,
}

---@type { path: string|nil, reason: string|nil }|nil
local cached

--- The bash to run `.sh` scripts with (memoized). Never the WSL launcher.
---@return string|nil path  Git Bash on Windows, `bash` elsewhere
---@return string|nil reason  when nothing was found
function M.find()
  if not cached then
    -- The PATH lookups (`vim.fn`) and `vim.system():wait()` raise E5560 in a fast event; not cached, so the
    -- next call from the main loop does the lookup.
    if vim.in_fast_event() then
      return nil, "cross.bash() is not callable in a fast event (call it from the main loop)"
    end
    local path, reason = M.locate(system_io)
    cached = { path = path, reason = reason }
  end
  return cached.path, cached.reason
end

--- Drop the memoized result (after installing Git, or in specs).
---@return nil
function M.clear()
  cached = nil
end

return M
