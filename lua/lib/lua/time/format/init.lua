---@module 'lib.lua.time.format'
--- Format a unix timestamp using a small set of named style presets, pure
--- Lua (`os.date`), no `vim.*`.

---@type LibTimeFormat
local M = {}

---@type table<string, string>
local PATTERNS = {
  iso = "%Y-%m-%dT%H:%M:%S",
  human = "%b %d, %Y %H:%M",
  short = "%Y-%m-%d",
  log = "[%Y-%m-%d %H:%M:%S]",
  filename = "%Y%m%d_%H%M%S",
}

---Format a unix timestamp.
---@nodiscard
---@param ts? integer Defaults to `os.time()`
---@param fmt? LibTimeFormatStyle Defaults to `"iso"` for unrecognized/nil values
---@param opts? LibTimeFormatOpts
---@return string
function M.format_timestamp(ts, fmt, opts)
  ts = ts or os.time()
  opts = opts or {}

  if fmt == "unix" then
    return tostring(ts)
  end

  local pattern = PATTERNS[fmt] or PATTERNS.iso
  if opts.utc then
    pattern = "!" .. pattern
  end

  return os.date(pattern, ts)
end

return M
