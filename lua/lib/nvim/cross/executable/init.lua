---@module 'lib.nvim.cross.executable'
--- Executable lookup helpers: PATH resolution and Mason-managed binaries.
---
--- Consolidates a pattern independently re-implemented in several plugins
--- (open.nvim's `util.find_exec`, dap.nvim's `utils.executable`): "is this
--- on PATH", "which of these candidates is", and "resolve a Mason-installed
--- binary's path, accounting for the .cmd suffix Mason uses on Windows".
---
--- Lookups are **memoized per name**. `vim.fn.executable()` / `vim.fn.exepath()`
--- walk every entry of $PATH and stat candidate filenames; on Windows each of
--- those stats also passes the AV filter driver, which makes a single call cost
--- milliseconds rather than microseconds. Config that asks "is this tool
--- available?" for a dozen language servers at startup pays that repeatedly and
--- synchronously on the main loop — measurably: ~13 ms of unattributed time per
--- cluster of checks in a `nvim --startuptime` log.
---
--- The trade-off: a tool installed (or removed) *during* a session is not
--- noticed until the cache is dropped. Call `clear()` after installing
--- something, or `clear(name)` for a single entry. Anything checking for a tool
--- it just installed itself should clear that name.

local M = {}

---@type table<string, boolean>
local exists_cache = {}

---@type table<string, string|false>  false = "looked up, not found"
local path_cache = {}

---Drop memoized lookups so the next call re-checks $PATH.
---Pass `name` to invalidate a single entry, or nothing to clear everything.
---@param name? string
---@return nil
function M.clear(name)
  if name == nil then
    exists_cache = {}
    path_cache = {}
    return
  end
  exists_cache[name] = nil
  path_cache[name] = nil
end

---True when `name` is found on PATH. Memoized; see `clear()`.
---@param name string
---@return boolean
function M.exists(name)
  local hit = exists_cache[name]
  if hit ~= nil then
    return hit
  end
  local found = vim.fn.executable(name) == 1
  exists_cache[name] = found
  return found
end

---Absolute path to `name` if it is on PATH, else nil. Memoized; see `clear()`.
---@param name string
---@return string|nil
function M.path(name)
  local hit = path_cache[name]
  if hit ~= nil then
    -- `false` is the cached "not on PATH" sentinel.
    return hit or nil
  end
  local exe = vim.fn.exepath(name)
  local resolved = (exe ~= "" and exe) or nil
  path_cache[name] = resolved or false
  return resolved
end

---Return the first executable found on PATH from a single name or a list
---of candidate names, or nil if none are found.
---@param name_or_candidates string|string[]
---@return string|nil
function M.find(name_or_candidates)
  if type(name_or_candidates) == "string" then
    return M.exists(name_or_candidates) and name_or_candidates or nil
  end
  for _, name in ipairs(name_or_candidates) do
    if M.exists(name) then
      return name
    end
  end
  return nil
end

---Resolve a Mason-managed binary's path (`stdpath("data")/mason/bin/<name>`,
---with a `.cmd` suffix on native Windows), or nil if it isn't installed.
---Deliberately NOT memoized: this is a direct `fs_stat` of one known path (no
---$PATH walk), and Mason installs binaries mid-session, which is exactly the
---case a cache would get wrong.
---@param package_name string
---@return string|nil
function M.mason_bin(package_name)
  local bin = vim.fn.stdpath("data") .. "/mason/bin/" .. package_name
  if require("lib.nvim.cross.platform.is_windows")() then
    bin = bin .. ".cmd"
  end

  local uv = vim.uv or vim.loop
  local ok, stat = pcall(uv.fs_stat, bin)
  if ok and stat then
    return bin
  end
  return nil
end

return M
