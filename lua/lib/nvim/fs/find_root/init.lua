---@module 'lib.nvim.fs.find_root'
--- Cached, marker-based project-root finder.
---
--- Given a file (or directory) path, walks upward to the nearest ancestor that
--- contains any of the configured marker names (default `.git`) and returns that
--- ancestor directory. Results are cached per *directory* in an LRU cache — every
--- file in a directory shares the same root, so a session opening many files
--- across a project computes each directory's root at most once.
---
--- Factory usage:
---   local find_root = require("lib.nvim.fs.find_root")
---   local finder = find_root({ markers = { ".git" } })
---   local root = finder.find("/repo/src/a.lua")  -- "/repo"
---
--- See @types/init.lua for Lib.Fs.FindRoot / Lib.Fs.FindRoot.Opts.

local find_upward_dir = require("lib.nvim.fs.find_upward_dir")
local lru = require("lib.lua.memo.lru")

---@param opts Lib.Fs.FindRoot.Opts?
---@return Lib.Fs.FindRoot
return function(opts)
  opts = opts or {}
  local markers  = opts.markers or { ".git" }
  local capacity = opts.capacity or 256
  local use_cache = opts.cache ~= false

  ---@type Lib.Memo.Lru?
  local cache = use_cache and lru.new(capacity) or nil

  ---Resolve the directory to search from: the path itself when it is a
  ---directory, otherwise its parent.
  ---@param path string
  ---@return string
  local function dir_of(path)
    if vim.fn.isdirectory(path) == 1 then return path end
    return vim.fn.fnamemodify(path, ":h")
  end

  ---@param path string
  ---@return string|nil
  local function find(path)
    if type(path) ~= "string" or path == "" then return nil end
    local dir = dir_of(path)

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
