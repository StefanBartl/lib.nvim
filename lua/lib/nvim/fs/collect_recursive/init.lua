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
---```

require("lib.nvim.fs.collect_recursive.@types")

local uv = vim.uv or vim.loop

local M = {}

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

---@type Lib.Fs.CollectRecursive
return M
