---@module 'lib.nvim.cross.bash'
--- Locate the bash that runs `.sh` scripts: Git Bash on Windows, `bash` elsewhere.
---
--- On Windows the `bash` on PATH is often `C:\Windows\System32\bash.exe` (or
--- the `WindowsApps` alias), the WSL launcher: it starts a Linux distribution,
--- cannot read Windows script paths and fails without one installed. A caller
--- that wants to run `scripts/ci.sh` needs Git Bash. Candidates, in order:
---
---   1. `$ProgramFiles/Git/bin/bash.exe`
---   2. `$ProgramW6432/Git/bin/bash.exe` (a 32-bit process sees the x86 folder above)
---   3. derived from `git --exec-path` (`<root>/<mingw64|clangarm64|...>/libexec/git-core`
---      -> `<root>/bin/bash.exe`, else `<root>/usr/bin/bash.exe`; covers scoop,
---      portable, ARM64, MSYS2 and custom installs)
---   4. `C:/Program Files/Git/bin/bash.exe`
---   5. `bash` on PATH, unless it is the WSL launcher
---
--- Elsewhere the answer is `bash` when it is on PATH.
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
  if not io.is_windows() then
    if io.exepath("bash") then
      return "bash"
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
    if not M.is_wsl_launcher(candidate) and io.is_file(candidate) then
      return candidate
    end
    return nil
  end

  for _, var in ipairs({ "ProgramFiles", "ProgramW6432" }) do
    local base = io.getenv(var)
    local hit = base and base ~= "" and try(slashes(base):gsub("/+$", "") .. "/Git/bin/bash.exe")
    if hit then
      return hit
    end
  end

  local exec_path = io.git_exec_path()
  local root = exec_path and git_root(exec_path)
  -- Git for Windows has `<root>/bin/bash.exe`; an MSYS2 install only `<root>/usr/bin/bash.exe`.
  local hit = root and (try(root .. "/bin/bash.exe") or try(root .. "/usr/bin/bash.exe"))
  if hit then
    return hit
  end

  hit = try("C:/Program Files/Git/bin/bash.exe")
  if hit then
    return hit
  end

  local on_path = io.exepath("bash")
  if on_path then
    if M.is_wsl_launcher(on_path) then
      tried[#tried + 1] = slashes(on_path) .. " (WSL launcher, skipped)"
    else
      hit = try(on_path)
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
