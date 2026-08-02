---@module 'lib.nvim.telemetry.report_file'
--- Where a rendered Markdown report lives on disk, and writing one there.
---
--- A separate artifact from the JSON counters `store.lua` persists — this is
--- what `report_file = true` (periodic, at every flush) and `:LibTelemetry
--- open` (on demand) both write, and what `renderers/mdview.lua` hands to
--- `:MDView standalone` to watch. Deliberately its own file: the JSON store
--- answers "what happened", this answers "where does the human-readable
--- version of that live" — different question, different lifetime (this one
--- is disposable; delete it and the next flush or `open` rebuilds it).

local store = require("lib.nvim.telemetry.store")

local M = {}

---@param opts? Lib.Cache.Opts
---@return string
function M.dir(opts)
  local root = (opts and opts.dir) or (vim.fn.stdpath("cache") .. "/lib.nvim")
  return root .. "/telemetry"
end

---@param namespace string
---@param opts? Lib.Cache.Opts
---@return string
function M.namespace_path(namespace, opts)
  return M.dir(opts) .. "/" .. store.sanitize(namespace) .. ".md"
end

---The combined, all-instances document `:LibTelemetry open` (no namespace)
---renders — a snapshot at invocation time, not self-updating like a
---per-namespace file can be. See the "Browser report" section of
---lua/lib/nvim/telemetry/README.md for why only the per-namespace path can
---be a live `:MDView standalone` target.
---@param opts? Lib.Cache.Opts
---@return string
function M.combined_path(opts)
  return M.dir(opts) .. "/report.md"
end

---Best-effort: never raises. A report file is a convenience artifact, not
---data — a write failure (a locked file, a full disk) must not take down
---the flush that triggered it.
---@param path string
---@param lines string[]
---@return boolean ok, string|nil err
function M.write(path, lines)
  local dir = vim.fn.fnamemodify(path, ":h")
  local ok_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    return false, "failed to create directory: " .. dir
  end

  local ok, err = pcall(function()
    local file = assert(io.open(path, "w"))
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
  end)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M
