---@module 'lib.nvim.deps.project.walk'
--- The walk behind `lib.nvim.deps.project.scan`: one asynchronous pass over a
--- root that COUNTS while it goes (files per kind plus one sample path each,
--- never a path list), stops at a file, depth or time limit, can be
--- cancelled, and answers exactly once -- also when something inside the walk
--- throws (a caller's `ignore` function, say). `lib.nvim.fs.collect_recursive`
--- has none of those three properties, and a scan wired to `DirChanged` needs
--- all of them: a `:cd ~` must not start an unbounded walk that keeps every
--- path in memory, and a walk that died must not leave its waiters hanging.
---
--- Symlinked directories are counted as directories but never entered (the
--- ERR-34 rule of `collect_recursive`: a link can point at an ancestor).

local uv = vim.uv or vim.loop
local async = require("lib.nvim.async")
local await = async.await

local M = {}

---Limits a walk uses when the caller names none.
---@type { max_files: integer, max_depth: integer, max_ms: integer }
M.DEFAULTS = { max_files = 100000, max_depth = 32, max_ms = 30000 }

---The key a file counts under: `"*.lua"` for a file with an extension (the
---last one, lower-cased), the bare name (`"Makefile"`, `".gitignore"`) for one
---without.
---@param path string
---@return string key
function M.key_of(path)
  local name = path:match("([^/\\]+)$") or path
  local ext = name:match("^.+%.([^.]+)$")
  if ext then
    return "*." .. ext:lower()
  end
  return name
end

---Count one file into `keys`.
---@param keys table<string, Lib.Deps.Project.KeyCount>
---@param path string
---@return nil
function M.add(keys, path)
  local key = M.key_of(path)
  local entry = keys[key]
  if entry then
    entry.count = entry.count + 1
  else
    keys[key] = { count = 1, sample = path }
  end
end

---@internal
---Is this entry a directory, and is it a symlink. Only a `link` hint, or no
---hint at all, costs a stat.
---@param abs_path string
---@param kind_hint string|nil
---@return boolean is_dir
---@return boolean is_symlink
local function classify(abs_path, kind_hint)
  if kind_hint == "directory" then
    return true, false
  elseif kind_hint == "file" then
    return false, false
  elseif kind_hint == "link" then
    local _, st = await(function(resume)
      uv.fs_stat(abs_path, resume)
    end)
    return (st and st.type == "directory") or false, true
  end
  local _, lst = await(function(resume)
    uv.fs_lstat(abs_path, resume)
  end)
  if lst and lst.type == "link" then
    local _, st = await(function(resume)
      uv.fs_stat(abs_path, resume)
    end)
    return (st and st.type == "directory") or false, true
  end
  return (lst and lst.type == "directory") or false, false
end

---Walk `root` and count its files.
---
---`opts.ignore(abs_path, is_dir)` prunes an entry (a directory with its whole
---subtree). It runs inside a libuv callback, so it must not call `vim.fn` or
---`vim.api`; if it throws, the walk ends there and the result carries
---`failed`.
---
---`on_done(result)` fires once, on the main loop, never after `cancel()`.
---@param root string normalized root
---@param opts? Lib.Deps.Project.WalkOpts
---@param on_done fun(result: Lib.Deps.Project.WalkResult)
---@return fun() cancel
function M.run(root, opts, on_done)
  opts = opts or {}
  local max_files = opts.max_files or M.DEFAULTS.max_files
  local max_depth = opts.max_depth or M.DEFAULTS.max_depth
  local max_ms = opts.max_ms or M.DEFAULTS.max_ms
  local ignore = opts.ignore
  local deadline = uv.hrtime() + max_ms * 1e6

  ---@type Lib.Deps.Project.WalkResult
  local result = { keys = {}, total = 0, errors = {}, root_unreadable = false }
  local cancelled, settled, stopped = false, false, false

  local function finish()
    if settled or cancelled then
      return
    end
    settled = true
    if #result.errors == 0 then
      result.errors = nil
    end
    on_done(result)
  end

  ---Stop the whole walk for `reason`; the first reason wins.
  ---@param reason "max_files"|"max_ms"
  local function stop(reason)
    stopped = true
    result.truncated = reason
  end

  ---@param dir string
  ---@param depth integer 0 for the root
  local function walk(dir, depth)
    local err, handle = await(function(resume)
      uv.fs_scandir(dir, resume)
    end)
    if err or not handle then
      result.errors[#result.errors + 1] = dir .. ": " .. tostring(err or "scandir failed")
      if depth == 0 then
        result.root_unreadable = true
      end
      return
    end
    while not cancelled and not stopped do
      if uv.hrtime() > deadline then
        stop("max_ms")
        return
      end
      local name, kind_hint = uv.fs_scandir_next(handle)
      if not name then
        return
      end
      local abs_path = dir .. "/" .. name
      local is_dir, is_symlink = classify(abs_path, kind_hint)
      if not (ignore ~= nil and ignore(abs_path, is_dir)) then
        if is_dir then
          if is_symlink then
            -- ERR-34: a symlinked directory is never entered (deliberate no-op).
          elseif depth + 1 > max_depth then
            -- Pruned, not stopped: the rest of the tree is still walked.
            result.truncated = result.truncated or "max_depth"
          else
            walk(abs_path, depth + 1)
          end
        else
          if result.total >= max_files then
            stop("max_files")
            return
          end
          result.total = result.total + 1
          M.add(result.keys, abs_path)
        end
      end
    end
  end

  -- `on_error` is what keeps a throwing walk from going silent: `async.run`
  -- never calls `on_done` for a body that raised, and the waiters of
  -- `project.scan` would hang on it forever.
  local run_opts = {
    tag = "lib.nvim.deps.project",
    on_error = function(err)
      result.failed = tostring(err)
      vim.schedule(finish)
    end,
  }
  async.run(function()
    walk(root, 0)
  end, finish, run_opts)

  return function()
    cancelled = true
  end
end

return M
