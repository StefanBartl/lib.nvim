---@module 'lib.nvim.logger.record'
--- Build a normalized log record from a call. Kept separate so the factory's
--- hot path stays readable and the record shape lives in one place.

local serialize = require("lib.nvim.logger.serialize")

local M = {}

local LEVEL_NAME = {
  [vim.log.levels.TRACE] = "TRACE",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.ERROR] = "ERROR",
}

---@param level integer
---@return string
function M.level_name(level)
  return LEVEL_NAME[level] or ("LVL" .. tostring(level))
end

---Resolve `ctx`, which may be a table or a thunk returning a table.
---The thunk form lets callers defer expensive context building to after the
---level gate, so it costs nothing when the level is inactive.
---@param ctx table|fun():table|nil
---@return table|nil
local function resolve_ctx(ctx)
  if type(ctx) == "function" then
    local ok, val = pcall(ctx)
    if ok and type(val) == "table" then
      return val
    end
    return { ctx_error = tostring(val) }
  end
  if type(ctx) == "table" then
    return ctx
  end
  return nil
end

---Build a record. `src` (file:line) is only computed when requested, since
---`debug.getinfo` is not free.
---@param scope string
---@param level integer
---@param msg string
---@param ctx table|fun():table|nil
---@param opts Lib.Logger.CallOpts|nil
---@param want_src boolean
---@param redact string[]|nil
---@param src_level integer  # debug.getinfo stack level of the original caller
---@return Lib.Logger.Record
function M.build(scope, level, msg, ctx, opts, want_src, redact, src_level)
  if type(msg) ~= "string" then
    msg = tostring(msg)
  end

  local raw_ctx = resolve_ctx(ctx)

  ---@type Lib.Logger.Record
  local record = {
    ts = os.time(),
    mono = vim.uv and vim.uv.hrtime() or 0,
    iso = os.date("%Y-%m-%d %H:%M:%S"),
    level = level,
    level_name = M.level_name(level),
    scope = scope,
    msg = msg,
    ctx = serialize.sanitize_ctx(raw_ctx, redact),
    tags = opts and opts.tags or nil,
  }

  if want_src then
    local info = debug.getinfo(src_level, "Sl")
    if info then
      record.src = string.format("%s:%d", info.short_src or "?", info.currentline or -1)
    end
  end

  return record
end

return M
