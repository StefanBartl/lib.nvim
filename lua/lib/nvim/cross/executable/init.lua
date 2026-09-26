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
---
--- Memoizing does not help the FIRST lookup of each name, and a name that is
--- not installed is the expensive one (every $PATH entry x every $PATHEXT
--- extension, ~40 ms measured). On native Windows the time spent in native
--- lookups is therefore added up, and once it reaches what an index of $PATH
--- costs to build (`executable.index`, ~30-65 ms) the index is built right
--- there, synchronously: from then on every not-yet-seen name is answered from
--- a table. Synchronously, because the typical caller is a loop over a dozen
--- names (dap adapters, language servers) that never yields to the event loop --
--- a background build could not finish inside it. Never spending more on native
--- lookups than the index costs is the point; `warm()` builds it ahead of time.
--- The index expires (see `index.MAX_AGE_MS`) and is dropped when $PATH changes;
--- whatever it cannot answer goes to `vim.fn` as before.

local index = require("lib.nvim.cross.executable.index")

local M = {}

--- Milliseconds of native lookups after which the index is cheaper: about what
--- building it costs (30-65 ms measured), so the total is never more than twice
--- what the cheapest strategy in hindsight would have paid.
local INDEX_BREAKEVEN_MS = 60

---@type number  ms spent in native lookups so far
local native_ms = 0

---@type table<string, boolean>  names that must skip the index (cleared by name)
local bypass = {}

---Account for one native lookup that took `ms`; on Windows, build the index
---once the native lookups have cost as much as it would.
---@param ms number
---@return nil
local function note_native(ms)
  native_ms = native_ms + ms
  if native_ms >= INDEX_BREAKEVEN_MS and index.supported() and not index.ready() then
    index.build()
  end
end

---@return number ms
local function now_ms()
  return (vim.uv or vim.loop).hrtime() / 1e6
end

---Ask the index for `name`, unless the caller cleared that name (a tool
---installed a moment ago is not in an index built before it). The entry stays
---until a full `clear()`: `exists` and `path` both look the name up once.
---@param name string
---@return string|nil path
---@return boolean known
local function from_index(name)
  if bypass[name] then
    return nil, false
  end
  return index.lookup(name)
end

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
    bypass = {}
    native_ms = 0
    index.reset()
    return
  end
  exists_cache[name] = nil
  path_cache[name] = nil
  bypass[name] = true
end

---Build the $PATH index in the background now (native Windows only; a no-op
---elsewhere). For a caller that knows it is about to ask for many names, e.g.
---a health check listing every configured tool.
---@return nil
function M.warm()
  index.build_async()
end

---True when `name` is found on PATH. Memoized; see `clear()`.
---@param name string
---@return boolean
function M.exists(name)
  local hit = exists_cache[name]
  if hit ~= nil then
    return hit
  end
  local resolved, known = from_index(name)
  local found
  if known then
    found = resolved ~= nil
  else
    local t0 = now_ms()
    found = vim.fn.executable(name) == 1
    note_native(now_ms() - t0)
  end
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
  local resolved, known = from_index(name)
  if not known then
    local t0 = now_ms()
    local exe = vim.fn.exepath(name)
    resolved = (exe ~= "" and exe) or nil
    note_native(now_ms() - t0)
  end
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

---@type Lib.Cross.Executable
return M
