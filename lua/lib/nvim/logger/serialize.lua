---@module 'lib.nvim.logger.serialize'
--- Turn arbitrary Lua values into JSON-safe data, then into a JSONL line.
---
--- `vim.json.encode` cannot handle functions, userdata, threads or cyclic
--- tables, so `sanitize` runs first: it stringifies the non-encodable types,
--- breaks cycles, caps depth/width, and scrubs redacted keys. The file sink and
--- the machine-readable dump both go through `encode`; the inspector uses
--- `human`.

local M = {}

--- Defaults for the two caps `sanitize` applies, overridable per call.
---
--- Per call rather than through a library-wide setting: this is a library,
--- and the right width for one log line is a property of what is being
--- logged, not of the process doing it. `lib.lua.dump.to_lines` takes
--- `max_depth` the same way.
local MAX_DEPTH = 8
local MAX_ITEMS = 200 -- per table, guards against dumping a whole buffer table

---@class Lib.Logger.SanitizeOpts
---@field max_depth? integer  # Nesting levels kept before `"<max-depth>"` (default 8).
---@field max_items? integer  # Entries kept per table before `"<truncated>"` (default 200).

---@internal
---Recursively convert `value` into something `vim.json.encode` accepts.
---@param value any
---@param redact table<string, true>|nil  # keys to replace with "<redacted>"
---@param depth integer
---@param seen table   # identity set for cycle detection
---@param limits { max_depth: integer, max_items: integer }
---@return any
local function sanitize(value, redact, depth, seen, limits)
  local t = type(value)

  if t == "string" or t == "boolean" then
    return value
  elseif t == "number" then
    -- JSON has no NaN/Inf; stringify those so encode never fails.
    if value ~= value or value == math.huge or value == -math.huge then
      return tostring(value)
    end
    return value
  elseif t == "nil" then
    return nil
  elseif t == "function" then
    return "<function>"
  elseif t == "thread" then
    return "<thread>"
  elseif t == "userdata" then
    return "<userdata>"
  elseif t ~= "table" then
    return tostring(value)
  end

  -- table
  if seen[value] then
    return "<cycle>"
  end
  if depth >= limits.max_depth then
    return "<max-depth>"
  end
  seen[value] = true

  local out = {}
  local count = 0
  -- Preserve array-ness: encode returns [] for empty, {} otherwise — vim.json
  -- treats an empty table as an object, which is fine for our records.
  local is_array
  if vim.islist then
    is_array = vim.islist(value)
  -- The deprecation is why this branch is guarded: it only runs on builds
  -- too old to have `vim.islist`.
  ---@diagnostic disable-next-line: deprecated
  elseif vim.tbl_islist then
    ---@diagnostic disable-next-line: deprecated
    is_array = vim.tbl_islist(value)
  else
    is_array = false
  end
  if is_array then
    for i = 1, #value do
      count = count + 1
      if count > limits.max_items then
        out[#out + 1] = "<truncated>"
        break
      end
      out[i] = sanitize(value[i], redact, depth + 1, seen, limits)
    end
  else
    for k, v in pairs(value) do
      count = count + 1
      if count > limits.max_items then
        out["<truncated>"] = true
        break
      end
      local key = type(k) == "string" and k or tostring(k)
      if redact and redact[key] then
        out[key] = "<redacted>"
      else
        out[key] = sanitize(v, redact, depth + 1, seen, limits)
      end
    end
  end

  seen[value] = nil
  return out
end

---Sanitize a context table for safe logging.
---@param ctx table|nil
---@param redact string[]|nil
---@param opts Lib.Logger.SanitizeOpts|nil  # Per-call caps; see the defaults above.
---@return table|nil
function M.sanitize_ctx(ctx, redact, opts)
  opts = opts or {}
  local limits = {
    max_depth = (type(opts.max_depth) == "number" and opts.max_depth > 0) and opts.max_depth
      or MAX_DEPTH,
    max_items = (type(opts.max_items) == "number" and opts.max_items > 0) and opts.max_items
      or MAX_ITEMS,
  }

  if ctx == nil then
    return nil
  end
  if type(ctx) ~= "table" then
    return { value = sanitize(ctx, nil, 0, {}, limits) }
  end
  local redact_set
  if redact and #redact > 0 then
    redact_set = {}
    for _, key in ipairs(redact) do
      redact_set[key] = true
    end
  end
  return sanitize(ctx, redact_set, 0, {}, limits)
end

---Encode a record to a single JSONL line (no trailing newline).
---Never throws: on encode failure it falls back to a minimal line.
---@param record Lib.Logger.Record
---@return string
function M.encode(record)
  local ok, line = pcall(vim.json.encode, record)
  if ok and type(line) == "string" then
    return line
  end
  -- Extremely defensive fallback — should not happen after sanitize.
  return string.format(
    '{"iso":%q,"level_name":%q,"scope":%q,"msg":%q,"encode_error":true}',
    tostring(record.iso),
    tostring(record.level_name),
    tostring(record.scope),
    tostring(record.msg)
  )
end

---Render a record as a compact human-readable line for the inspector / echo.
---@param record Lib.Logger.Record
---@return string
function M.human(record)
  local parts = {
    string.format("%s [%s] %s: %s", record.iso, record.level_name, record.scope, record.msg),
  }
  if record.tags and #record.tags > 0 then
    parts[#parts + 1] = "#" .. table.concat(record.tags, " #")
  end
  if record.ctx and next(record.ctx) ~= nil then
    parts[#parts + 1] = vim.inspect(record.ctx, { newline = " ", indent = "" })
  end
  return table.concat(parts, "  ")
end

return M
