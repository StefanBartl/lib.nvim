---@module 'lib.nvim.fs.find_root'
--- Cached, marker-based project-root finder.
---
--- Given a file (or directory) path, walks upward to the nearest ancestor that
--- contains any of the configured marker names (default `.git`) and returns that
--- ancestor directory. Results are cached per *directory* in an LRU cache — every
--- file in a directory shares the same root, so a session opening many files
--- across a project computes each directory's root at most once.
---
--- Markers may be globs (`*.rockspec`) — see `find_upward_dir.matcher`.
---
--- With `cache_chain = true` the walk is performed here instead of being
--- delegated to `vim.fs.find`, which lets *every* directory passed on the way
--- up be cached, not just the one that was queried. That turns the second
--- lookup anywhere inside an already-visited subtree into a cache hit.
---
--- Two optional bounds keep the walk from producing an unwanted root:
---
---   * `skip_dirs` — vendor directories that must never contain a root.
---     Without it, a file in `/repo/node_modules/pkg/lib/x.js` resolves to
---     `/repo/node_modules/pkg` (it has a `package.json`), which is a
---     dependency, not the project. The walk therefore starts *above* the
---     topmost such directory in the path — nested copies included.
---   * `max_depth` — how many levels the walk may climb. Cheap insurance
---     against a stray path walking to the filesystem root (or across a
---     network mount) before giving up.
---
--- Factory usage:
---   local find_root = require("lib.nvim.fs.find_root")
---   local finder = find_root({ markers = { ".git", "*.rockspec" } })
---   local root = finder.find("/repo/src/a.lua")  -- "/repo"
---
--- See @types/init.lua for Lib.Fs.FindRoot / Lib.Fs.FindRoot.Opts.

require("lib.nvim.fs.find_root.@types")

local find_upward_dir = require("lib.nvim.fs.find_upward_dir")
local matcher = require("lib.nvim.fs.find_upward_dir.matcher")
local lru = require("lib.lua.memo.lru")

---@param opts Lib.Fs.FindRoot.Opts?
---@return Lib.Fs.FindRoot
return function(opts)
  opts = opts or {}
  local markers = opts.markers or { ".git" }
  local cache_chain = opts.cache_chain == true
  -- A chain walk inserts one entry per visited directory, so the same LRU
  -- would evict far sooner. Give it more headroom by default.
  local capacity = opts.capacity or (cache_chain and 512 or 256)
  local use_cache = opts.cache ~= false

  ---@type Lib.Memo.Lru?
  local cache = use_cache and lru.new(capacity) or nil

  local matches = matcher.build(markers)

  ---@type table<string, true>?
  local skip = nil
  if opts.skip_dirs and #opts.skip_dirs > 0 then
    skip = {}
    for _, name in ipairs(opts.skip_dirs) do
      skip[name] = true
    end
  end

  local max_depth = opts.max_depth

  ---@internal
  ---Resolve the directory to search from: the path itself when it is a
  ---directory, otherwise its parent.
  ---@param path string
  ---@return string
  local function dir_of(path)
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
    return vim.fn.fnamemodify(path, ":h")
  end

  ---@internal
  ---Where the upward walk actually begins.
  ---
  ---With `skip_dirs`, anything at or below such a directory is off limits, so
  ---the walk restarts at the parent of its **topmost** occurrence — topmost,
  ---not nearest, so nested vendor trees (`a/node_modules/b/node_modules/c`)
  ---resolve to the outer project in one step. Pure string work: no filesystem
  ---access, and the answer is still cached under the originally queried
  ---directory.
  ---@param dir string
  ---@return string
  local function start_at(dir)
    if not skip then
      return dir
    end
    local normalized = vim.fs.normalize(dir)
    local prefix = normalized:match("^(%a:)") or (normalized:sub(1, 1) == "/" and "/" or "")
    local out = prefix
    for segment in normalized:sub(#prefix + 1):gmatch("[^/]+") do
      if skip[segment] then
        -- `out` is the parent of the topmost skipped directory; everything
        -- below it is vendored, so the walk starts here.
        return out == "" and "." or out
      end
      out = (out == "" or out == "/") and (out .. segment) or (out .. "/" .. segment)
    end
    return dir
  end

  ---@internal
  ---The ancestor `max_depth` levels above `dir`, or nil when unbounded.
  ---
  ---Expressed as `vim.fs.find`'s `stop` directory — which is itself excluded
  ---— so the bound survives on the fast path instead of forcing a manual
  ---walk. `max_depth = 0` means "only `dir` itself".
  ---@param dir string
  ---@return string?
  local function stop_dir(dir)
    if not max_depth then
      return nil
    end
    local current = dir
    for _ = 0, max_depth do
      local parent = vim.fs.dirname(current)
      if not parent or parent == current then
        return nil -- the bound reaches past the filesystem root: unbounded
      end
      current = parent
    end
    return current
  end

  ---@internal
  ---True when `dir` directly contains any marker.
  ---@param dir string
  ---@return boolean
  local function holds_marker(dir)
    for name in vim.fs.dir(dir) do
      if matches(name) then
        return true
      end
    end
    return false
  end

  ---@internal
  ---Walk upward from `dir`, caching the root for every directory passed.
  ---@param dir string
  ---@return string|nil
  local function find_chain(dir)
    local visited = {}
    local current = dir
    local root
    local steps = 0

    while current do
      if max_depth and steps > max_depth then
        break
      end
      if cache then
        local hit = cache:get(current)
        if hit ~= nil then
          -- Reuse an already-known answer for this ancestor (`false` is the
          -- cached "no root found" sentinel) instead of walking further.
          root = hit or nil
          break
        end
      end

      visited[#visited + 1] = current

      -- `vim.fs.dir` throws on an unreadable directory; that is a "no marker
      -- here", not a failure of the whole walk.
      local ok, found = pcall(holds_marker, current)
      if ok and found then
        root = current
        break
      end

      local parent = vim.fs.dirname(current)
      -- `dirname` is a fixed point at the filesystem root — that is the stop
      -- condition, not an error.
      if not parent or parent == current then
        break
      end
      current = parent
      steps = steps + 1
    end

    if cache then
      local value = root or false
      for _, seen in ipairs(visited) do
        cache:put(seen, value)
      end
    end

    return root
  end

  ---@internal
  ---@param path string
  ---@return string|nil
  local function find(path)
    if type(path) ~= "string" or path == "" then
      return nil
    end
    local dir = dir_of(path)

    -- Cached under the *queried* directory, before `skip_dirs` redirects the
    -- walk: the caller asked about `dir`, and that is the key they will hit
    -- again. Checked here rather than inside find_chain so both strategies
    -- short-circuit on the same key.
    if cache and not cache_chain then
      local hit = cache:get(dir)
      if hit ~= nil then
        -- `false` is the cached "no root found" sentinel.
        return hit or nil
      end
    end

    local from = start_at(dir)

    if cache_chain then
      local root = find_chain(from)
      -- The chain caches what it walked; when skip_dirs moved the start, the
      -- queried directory itself was never visited and still needs its entry.
      if cache and from ~= dir then
        cache:put(dir, root or false)
      end
      return root
    end

    local root = find_upward_dir(markers, from, { stop = stop_dir(from) })

    if cache then
      cache:put(dir, root or false)
    end
    return root
  end

  ---@internal
  ---Drop all cached root lookups (e.g. after markers change on disk).
  local function clear()
    if cache then
      cache = lru.new(capacity)
    end
  end

  return { find = find, clear = clear }
end
