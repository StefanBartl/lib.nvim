---@module 'lib.nvim.logger.sinks'
--- Output backends for a logger. Each sink receives already-built, already-
--- sanitized records; level/enabled/tag gating happens in the factory before a
--- record ever reaches here.
---
---   - notify : surface the message through lib.nvim.notify (fast-event safe)
---   - file   : append JSONL lines via lib.nvim.fs.write.append

local serialize = require("lib.nvim.logger.serialize")

local M = {}

-- ---------------------------------------------------------------------------
-- notify sink
-- ---------------------------------------------------------------------------

-- Use the scheduled/safe notifier so logging from CursorMoved / LSP callbacks /
-- other fast contexts can never break vim.notify.
local safe = require("lib.nvim.notify.safe")

local LEVEL_METHOD = {
  [vim.log.levels.TRACE] = "debug",
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.INFO] = "info",
  [vim.log.levels.WARN] = "warn",
  [vim.log.levels.ERROR] = "error",
}

---Build a notify sink bound to a prefix.
---@param name string
---@return fun(record: Lib.Logger.Record)
function M.notifier(name)
  local prefix = ("[%s]"):format(name)
  local notifier = safe.create_safe(prefix)
  return function(record)
    local method = LEVEL_METHOD[record.level] or "info"
    notifier[method](record.msg)
  end
end

-- ---------------------------------------------------------------------------
-- file sink
-- ---------------------------------------------------------------------------

local append = require("lib.nvim.fs.write.append")

---Resolve the default log-file path for a logger name (cross-platform).
---@param name string
---@return string
function M.default_path(name)
  local dir = vim.fn.stdpath("log")
  local sep = package.config:sub(1, 1) -- "\\" on Windows, "/" elsewhere
  return table.concat({ dir, "lib-logger", name .. ".jsonl" }, sep)
end

---Append one record to `path` as a JSONL line. Synchronous and defensive.
---@param path string
---@param record Lib.Logger.Record
---@return boolean ok
---@return string|nil err
function M.write_record(path, record)
  return append(path, serialize.encode(record))
end

---Append many records to `path` in one open/close (used by flush / crash dump).
---@param path string
---@param records Lib.Logger.Record[]
---@return boolean ok
---@return string|nil err
function M.write_records(path, records)
  if #records == 0 then
    return true, nil
  end
  local lines = {}
  for i = 1, #records do
    lines[i] = serialize.encode(records[i])
  end
  return append(path, table.concat(lines, "\n"))
end

return M
