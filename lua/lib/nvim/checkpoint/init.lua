---@module 'lib.nvim.checkpoint'
--- Snapshot a set of files before a destructive multi-file operation, so it
--- can be undone byte-exact if something goes wrong — for tools that
--- rewrite/move/delete across a whole project (a search-and-replace,
--- a bulk rename, an API migration) rather than a single buffer edit.
---
--- "Byte-exact" is the point of using `fs_copyfile` rather than reading
--- lines and writing them back: the latter can silently normalize line
--- endings or encoding on restore, which defeats the purpose of a backup.
---
--- Not transactional across a crash: the checkpoint's backup files live
--- under `stdpath("cache")`, so they survive the current session but are
--- not fsync'd/journaled. This covers "the operation went wrong, undo it"
--- (the common case), not "Neovim was killed mid-write".
---
--- Usage:
--- ```lua
--- local checkpoint = require("lib.nvim.checkpoint")
---
--- local cp, err = checkpoint.create({ "/proj/a.lua", "/proj/new.lua" })
--- if not cp then
---   vim.notify(err)
---   return
--- end
---
--- local ok = run_destructive_operation()
--- if ok then
---   checkpoint.discard(cp)
--- else
---   local restored, errors = checkpoint.restore(cp)
---   checkpoint.discard(cp)
--- end
--- ```

require("lib.nvim.checkpoint.@types")

local mutate = require("lib.nvim.cross.fs.mutate")
local token = require("lib.nvim.token")

local uv = vim.uv or vim.loop

local M = {}

---@internal
---@param opts Lib.Checkpoint.CreateOpts|nil
---@return string
local function root_dir(opts)
  return (opts and opts.dir) or (vim.fn.stdpath("cache") .. "/lib.nvim/checkpoints")
end

---Snapshot every existing file in `paths`. A path that does not yet exist
---is still tracked (as `existed = false`) so `M.restore` can delete it if
---the operation being guarded against goes on to create it.
---@param paths string[]
---@param opts? Lib.Checkpoint.CreateOpts
---@return Lib.Checkpoint|nil checkpoint
---@return string|nil err
function M.create(paths, opts)
  local id = token.gen_token(12)
  local dir = root_dir(opts) .. "/" .. id

  local ok_mkdir, err_mkdir = mutate.mkdir_p(dir)
  if not ok_mkdir then
    return nil, "checkpoint: failed to create '" .. dir .. "': " .. tostring(err_mkdir)
  end

  local entries = {}
  for i, path in ipairs(paths) do
    local stat = uv.fs_stat(path)
    if stat then
      local backup = dir .. "/" .. i .. ".bak"
      local ok_copy, err_copy = mutate.copy_file(path, backup)
      if not ok_copy then
        return nil, "checkpoint: failed to back up '" .. path .. "': " .. tostring(err_copy)
      end
      entries[i] = { path = path, backup = backup, existed = true, size = stat.size }
    else
      entries[i] = { path = path, backup = nil, existed = false }
    end
  end

  return {
    id = id,
    dir = dir,
    created_at = os.time(),
    entries = entries,
  }, nil
end

---Restore every file tracked by `checkpoint` to its state at `M.create`
---time: an existing file's bytes are copied back verbatim; a file that did
---not exist yet is deleted if the guarded operation went on to create it.
---
---Best-effort: one entry failing does not stop the rest from being
---attempted. Check `errors` (empty on full success) rather than only `ok`.
---@param checkpoint Lib.Checkpoint
---@return boolean ok
---@return Lib.Checkpoint.RestoreError[] errors
function M.restore(checkpoint)
  local errors = {}

  for _, entry in ipairs(checkpoint.entries) do
    if entry.existed then
      local ok, err = mutate.copy_file(entry.backup, entry.path)
      if not ok then
        errors[#errors + 1] = { path = entry.path, err = err }
      end
    elseif uv.fs_stat(entry.path) ~= nil then
      local ok, err = mutate.delete_file(entry.path)
      if not ok then
        errors[#errors + 1] = { path = entry.path, err = err }
      end
    end
  end

  return #errors == 0, errors
end

---Delete `checkpoint`'s backup files. Call this once the guarded operation
---either succeeded (backups no longer needed) or was already restored.
---@param checkpoint Lib.Checkpoint
---@return boolean ok
function M.discard(checkpoint)
  return vim.fn.delete(checkpoint.dir, "rf") == 0
end

---@type Lib.Checkpoint.Module
return M
