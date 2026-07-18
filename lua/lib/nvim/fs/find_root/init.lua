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
  local markers  = opts.markers or { ".git" }
  local cache_chain = opts.cache_chain == true
  -- A chain walk inserts one entry per visited directory, so the same LRU
  -- would evict far sooner. Give it more headroom by default.
  local capacity = opts.capacity or (cache_chain and 512 or 256)
  local use_cache = opts.cache ~= false

  ---@type Lib.Memo.Lru?
  local cache = use_cache and lru.new(capacity) or nil

  local matches = matcher.build(markers)

  ---Resolve the directory to search from: the path itself when it is a
  ---directory, otherwise its parent.
  ---@param path string
  ---@return string
  local function dir_of(path)
    if vim.fn.isdirectory(path) == 1 then return path end
    return vim.fn.fnamemodify(path, ":h")
  end

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

  ---Walk upward from `dir`, caching the root for every directory passed.
  ---@param dir string
  ---@return string|nil
  local function find_chain(dir)
    local visited = {}
    local current = dir
    local root

    while current do
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
    end

    if cache then
      local value = root or false
      for _, seen in ipairs(visited) do
        cache:put(seen, value)
      end
    end

    return root
  end

  ---@param path string
  ---@return string|nil
  local function find(path)
    if type(path) ~= "string" or path == "" then return nil end
    local dir = dir_of(path)

    if cache_chain then
      return find_chain(dir)
    end

    if cache then
      local hit = cache:get(dir)
      if hit ~= nil then
        -- `false` is the cached "no root found" sentinel.
        return hit or nil
      end
    end

    local root = find_upward_dir(markers, dir)

    if cache then
      cache:put(dir, root or false)
    end
    return root
  end

  local function clear()
    if cache then cache = lru.new(capacity) end
  end

  return { find = find, clear = clear }
end
