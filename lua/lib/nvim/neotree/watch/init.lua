---@module 'lib.nvim.neotree.watch'
--- Neo-tree file-watcher handle registry + proactive release.
---
--- Neo-tree opens one libuv `fs_event` handle per expanded directory
--- (`use_libuv_file_watcher = true`). On Windows each is an open
--- `ReadDirectoryChangesW` handle that keeps the directory open at the OS level.
--- Neo-tree's own `fs_watch.lua` only ever `:stop()`s these handles, never
--- `:close()`s them, so the OS handle lingers until Lua's GC runs — which is
--- why a rename/delete of a watched directory intermittently fails on Windows
--- with `EPERM` / `ERROR_SHARING_VIOLATION`: something still holds the handle.
---
--- This registry does two things:
---   1. `install()` wraps `fs_watch.watch_folder` to record every watcher
---      neo-tree creates, keyed by path, so we can find the handle for a path
---      later. It also wraps `stop_watching` to actually `:close()` the handles
---      neo-tree would otherwise leak.
---   2. `release(paths)` proactively closes the handle(s) on a path (and every
---      watched subpath) right before a filesystem mutation, releasing the OS
---      lock so the mutation can proceed. Meant to be driven from
---      `lib.nvim.cross.fs.mutate`'s `on_retry` hook: when a rename/delete hits
---      a transient sharing error, release the watcher and the retry succeeds.
---
--- Releasing must not leave neo-tree holding a *closed* handle it might
--- `:start()` again (that would crash), so `release` hands each neutralised
--- Watcher a fresh, unstarted `fs_event` — which holds nothing open until
--- started, so the lock stays released for the mutation window.
---
--- Neo-tree-specific by design (it patches a neo-tree internal), hence its home
--- under `lib.nvim.neotree`, next to `node`.

require("lib.nvim.neotree.watch.@types")

local uv = vim.uv or vim.loop

local M = {}

---path (normalized) → neo-tree Watcher object.
---@type table<string, Lib.Neotree.Watch.Watcher>
local registry = {}

---@type boolean
local _installed = false

---Normalize a path for prefix comparison: forward slashes, no trailing slash,
---lowercased drive letter. Neo-tree stores native-separator paths (backslash on
---Windows) while callers query with forward-slash paths — the same separator/
---case mismatch handled elsewhere in this codebase — so both sides must be
---normalized to one form before comparing.
---@param p string
---@return string
local function norm(p)
  if type(p) ~= "string" then return "" end
  p = (p:gsub("\\", "/")):gsub("/+$", "")
  p = p:gsub("^(%a):", function(d) return d:lower() .. ":" end)
  return p
end

---True when `path` is `base` itself or lives under it.
---@param base string
---@param path string
---@return boolean
local function under(base, path)
  base = norm(base)
  path = norm(path)
  if base == "" then return false end
  if path == base then return true end
  return path:sub(1, #base + 1) == base .. "/"
end

---Close a Watcher's OS handle, releasing the directory lock.
---
---`recreate = true`: hand the Watcher a fresh, unstarted `fs_event` afterward,
---because neo-tree keeps this Watcher in its own table and may `:start()` it
---again later (`updated_watched`) — doing so on a closed/nil handle would crash.
---A fresh fs_event holds nothing open until `:start()`, so the lock stays
---released for now.
---
---`recreate = false`: the caller knows neo-tree is discarding the Watcher (its
---`stop_watching` nuke), so no fresh handle is needed. Setting `active = false`
---keeps neo-tree's own `Watcher:stop()` from touching the nil handle.
---@param w Lib.Neotree.Watch.Watcher
---@param recreate boolean
local function release_watcher(w, recreate)
  if type(w) ~= "table" then return end
  local h = w.handle
  -- Stop first (no-op if not active); guarded — a bad handle must not throw.
  if w.active and h then
    pcall(function() h:stop() end)
  end
  w.active = false
  -- Close the OS handle. libuv closes asynchronously on the next loop tick, so
  -- a caller that needs the lock gone *now* must let the loop run (e.g.
  -- cross.fs.mutate's vim.wait backoff) before retrying.
  if h and not h:is_closing() then
    pcall(function() h:close() end)
  end
  if recreate then
    local ok, fresh = pcall(uv.new_fs_event)
    w.handle = ok and fresh or nil
  else
    w.handle = nil
  end
end

---Patch neo-tree's `fs_watch` so watchers are tracked and its close-leak is
---plugged. Idempotent; a no-op returning false when neo-tree's fs_watch module
---is unavailable (non-neotree setup, or called too early).
---@return boolean ok
function M.install()
  if _installed then return true end

  local ok, fs_watch = pcall(require, "neo-tree.sources.filesystem.lib.fs_watch")
  if not ok or type(fs_watch) ~= "table" then return false end
  if type(fs_watch.watch_folder) ~= "function" then return false end

  -- Record every watcher neo-tree creates. Wrapping (not replacing) keeps this
  -- composable with any other wrapper on watch_folder (e.g. an EPERM-swallowing
  -- callback wrap) — both call through to the original.
  local orig_watch = fs_watch.watch_folder
  fs_watch.watch_folder = function(path, callback)
    local w = orig_watch(path, callback)
    if type(w) == "table" then
      registry[norm(path)] = w
    end
    return w
  end

  -- Plug the leak on the nuclear path: neo-tree's stop_watching drops its whole
  -- watchers table without closing the OS handles. Close ours first.
  local orig_stop_all = fs_watch.stop_watching
  if type(orig_stop_all) == "function" then
    fs_watch.stop_watching = function(...)
      for key, w in pairs(registry) do
        release_watcher(w, false)
        registry[key] = nil
      end
      return orig_stop_all(...)
    end
  end

  _installed = true
  return true
end

---@return boolean
function M.installed()
  return _installed
end

---Close the file-watcher handle(s) on `paths` and every watched subpath,
---releasing the OS lock so a mutation on those paths can proceed. Safe to call
---when nothing is installed/tracked — it simply releases nothing.
---@param paths string|string[]
---@return integer released  How many watchers were released.
function M.release(paths)
  if type(paths) == "string" then paths = { paths } end
  if type(paths) ~= "table" then return 0 end

  local released = 0
  for key, w in pairs(registry) do
    local match = false
    for _, target in ipairs(paths) do
      if under(target, key) then
        match = true
        break
      end
    end
    if match then
      release_watcher(w, true)
      registry[key] = nil
      released = released + 1
    end
  end
  return released
end

---`release(paths)` → run `fn` → `release(paths)` again. The second release
---catches a watcher neo-tree may have re-established during `fn` (a refresh /
---rescan mid-operation), so a follow-up step (e.g. deleting both the old and
---new path) is not re-blocked. Re-raises any error from `fn` after releasing.
---@param paths string|string[]
---@param fn fun(): any
---@return any
function M.with_release(paths, fn)
  M.release(paths)
  local ok, res = pcall(fn)
  M.release(paths)
  if not ok then error(res) end
  return res
end

---Number of watchers currently tracked (diagnostics / tests).
---@return integer
function M.count()
  local n = 0
  for _ in pairs(registry) do n = n + 1 end
  return n
end

---Forget all tracked watchers without closing their handles (tests only).
function M.clear()
  registry = {}
end

return M
