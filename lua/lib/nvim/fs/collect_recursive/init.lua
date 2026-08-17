---@module 'lib.nvim.fs.collect_recursive'
--- Recursive directory walker built on `fs_scandir`/`fs_scandir_next`.
---
--- Returns a flat array of absolute paths under `root`. An optional
--- `ignore(abs_path, is_dir)` predicate can prune whole subtrees (returning
--- `true` for a directory skips both the directory entry itself and
--- everything under it).
---
---```lua
--- local collect_recursive = require("lib.nvim.fs.collect_recursive")
--- local all = collect_recursive.collect("/repo", { kind = "files" })
--- local files = collect_recursive.files("/repo", { ignore = function(p) return p:match("/%.git$") ~= nil end })
--- local dirs = collect_recursive.dirs("/repo")
---
--- -- Non-blocking counterpart, same options, for large trees (node_modules-
--- -- sized) where the synchronous walk above would stall the main loop:
--- local cancel = collect_recursive.collect_async("/repo", { kind = "files" }, function(paths)
---   -- called once, vim.schedule-dispatched
--- end)
---```

require("lib.nvim.fs.collect_recursive.@types")

local uv = vim.uv or vim.loop

local M = {}

---@internal
---Recursively walk `dir`, appending matching absolute paths into `out`.
---@param dir string
---@param opts Lib.Fs.CollectRecursive.Opts
---@param out string[]
local function walk(dir, opts, out)
  local handle = uv.fs_scandir(dir)
  if not handle then
    return
  end

  while true do
    local name, kind_hint = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local abs_path = dir .. "/" .. name

    -- `kind_hint` isn't always reliable across platforms/filesystems;
    -- fall back to `fs_stat` when it's missing or ambiguous.
    local is_dir
    if kind_hint == "directory" then
      is_dir = true
    elseif kind_hint == "file" then
      is_dir = false
    else
      local st = uv.fs_stat(abs_path)
      is_dir = (st and st.type == "directory") or false
    end

    if is_dir then
      local ignored = opts.ignore ~= nil and opts.ignore(abs_path, true) or false
      if not ignored then
        if opts.kind ~= "files" then
          out[#out + 1] = abs_path
        end
        walk(abs_path, opts, out)
      end
    else
      local ignored = opts.ignore ~= nil and opts.ignore(abs_path, false) or false
      if not ignored and opts.kind ~= "dirs" then
        out[#out + 1] = abs_path
      end
    end
  end
end

---Recursively collect absolute paths under `root`.
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@return string[]
function M.collect(root, opts)
  opts = opts or {}
  opts.kind = opts.kind or "all"

  local out = {}
  walk(root, opts, out)
  return out
end

---Convenience: collect only files.
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@return string[]
function M.files(root, opts)
  return M.collect(root, vim.tbl_extend("force", opts or {}, { kind = "files" }))
end

---Convenience: collect only directories.
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@return string[]
function M.dirs(root, opts)
  return M.collect(root, vim.tbl_extend("force", opts or {}, { kind = "dirs" }))
end

-- ============================================================================
-- Async walk — same result as `collect()`, without blocking the main loop.
--
-- `walk()` above is synchronous: `uv.fs_scandir`/`fs_stat` without a
-- callback block the caller until the syscall returns, which is fine for a
-- handful of directories but stalls Neovim's UI on a large tree (a
-- `node_modules`, a monorepo). The libuv calls below take a callback instead
-- and become genuinely async — the event loop keeps servicing input/redraws
-- while a scan is in flight — but chaining raw callbacks through recursive
-- directory descent produces exactly the callback-pyramid mess `fs/write/
-- async` was flagged for in the plenary/libuv research this was born from.
--
-- `lib.nvim.async` provides a minimal coroutine-based async/await:
-- `walk_async` below reads like the synchronous `walk()` above (plain
-- recursive calls, one `await()` per libuv call) while every `await()`
-- actually yields control back to the event loop.
--
-- That helper used to live here as a private copy (and a second, slightly
-- diverged one in `fs/write/async`); both were extracted into
-- `lib.nvim.async` once the duplication was real rather than hypothetical.
-- ============================================================================

local async = require("lib.nvim.async")
local await = async.await

---@internal
---Async counterpart to `walk()`. Same traversal/ignore/kind semantics;
---every `uv.fs_scandir`/`uv.fs_stat` call is awaited instead of blocking.
---@param dir string
---@param opts Lib.Fs.CollectRecursive.Opts
---@param out string[]
---@param is_cancelled fun(): boolean
local function walk_async(dir, opts, out, is_cancelled)
  if is_cancelled() then
    return
  end

  local scandir_err, handle = await(function(resume)
    uv.fs_scandir(dir, resume)
  end)
  if scandir_err or not handle then
    return
  end

  while true do
    if is_cancelled() then
      return
    end

    local name, kind_hint = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local abs_path = dir .. "/" .. name

    local is_dir
    if kind_hint == "directory" then
      is_dir = true
    elseif kind_hint == "file" then
      is_dir = false
    else
      local _, st = await(function(resume)
        uv.fs_stat(abs_path, resume)
      end)
      is_dir = (st and st.type == "directory") or false
    end

    if is_dir then
      local ignored = opts.ignore ~= nil and opts.ignore(abs_path, true) or false
      if not ignored then
        if opts.kind ~= "files" then
          out[#out + 1] = abs_path
        end
        walk_async(abs_path, opts, out, is_cancelled)
      end
    else
      local ignored = opts.ignore ~= nil and opts.ignore(abs_path, false) or false
      if not ignored and opts.kind ~= "dirs" then
        out[#out + 1] = abs_path
      end
    end
  end
end

---Async counterpart to `collect()`: same result, without blocking the main
---loop while it walks. `on_done(paths)` fires exactly once, `vim.schedule`-
---dispatched — never for a cancelled walk.
---
---This walks one directory at a time (async, not blocking, but not
---parallel either) — the fix for main-loop stalls on a large tree, not a
---wall-clock speedup; concurrent sibling scanning was left out to keep the
---coroutine driver simple (see the module-level comment above `await`).
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@param on_done fun(paths: string[])
---@return fun() cancel Stop after the current in-flight libuv call settles; `on_done` will not fire.
function M.collect_async(root, opts, on_done)
  opts = opts or {}
  opts.kind = opts.kind or "all"

  local cancelled = false
  local function is_cancelled()
    return cancelled
  end

  async.run(function()
    local out = {}
    walk_async(root, opts, out, is_cancelled)
    return out
  end, function(out)
    if not cancelled then
      on_done(out)
    end
  end, { tag = "lib.nvim.fs.collect_recursive" })

  return function()
    cancelled = true
  end
end

---Async convenience: collect only files.
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@param on_done fun(paths: string[])
---@return fun() cancel
function M.files_async(root, opts, on_done)
  return M.collect_async(root, vim.tbl_extend("force", opts or {}, { kind = "files" }), on_done)
end

---Async convenience: collect only directories.
---@param root string
---@param opts? Lib.Fs.CollectRecursive.Opts
---@param on_done fun(paths: string[])
---@return fun() cancel
function M.dirs_async(root, opts, on_done)
  return M.collect_async(root, vim.tbl_extend("force", opts or {}, { kind = "dirs" }), on_done)
end

---@type Lib.Fs.CollectRecursive
return M
