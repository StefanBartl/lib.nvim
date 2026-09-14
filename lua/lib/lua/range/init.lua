---@module 'lib.lua.range'
--- Parse a comma-separated list of positive integers and inclusive ranges
--- (`"1-3,5,7"`) into a sorted, deduplicated `integer[]`.
---
--- Editor-independent: no `vim` API, usable outside Neovim too. Reusable
--- anywhere a user types a short range spec and the caller needs a concrete
--- list — page ranges, line ranges, commit ranges.
---
--- Usage:
--- ```lua
--- local range = require("lib.lua.range")
---
--- local list = range.parse("1-3,5,7")   -- { 1, 2, 3, 5, 7 }
--- local list = range.parse("3-1")       -- { 1, 2, 3 } -- reversed range is normalized
--- local list, err = range.parse("x")    -- nil, "range: invalid token 'x'"
--- local list, err = range.parse("1-5", { max = 3 }) -- nil, "range: 5 is above max 3"
--- ```

local M = {}

---Parse `spec` into a sorted, deduplicated list of positive integers.
---@nodiscard
---@param spec string
---@param opts? Lib.Range.ParseOpts
---@return integer[]|nil list
---@return string|nil err
function M.parse(spec, opts)
  opts = opts or {}

  if type(spec) ~= "string" then
    return nil, "range: spec must be a string"
  end

  local trimmed = (spec:gsub("%s+", ""))
  if trimmed == "" then
    return nil, "range: empty spec"
  end

  -- Checked on each range's two endpoints *before* expanding it (not after,
  -- against the finished list): since a range is contiguous, both endpoints
  -- within [min, max] guarantees every value in between is too. Checking
  -- post-expansion let an out-of-bounds range (e.g. "1-50000000" against
  -- max=50) fully expand into a multi-million-entry table -- multiple
  -- seconds of blocked main loop -- before the bounds check ever ran,
  -- defeating the exact protection opts.min/opts.max exist to provide.
  ---@param n integer
  ---@return string|nil err
  local function check_bounds(n)
    if opts.min and n < opts.min then
      return "range: " .. n .. " is below min " .. opts.min
    end
    if opts.max and n > opts.max then
      return "range: " .. n .. " is above max " .. opts.max
    end
    return nil
  end

  local set = {}
  for token in (trimmed .. ","):gmatch("([^,]*),") do
    if token ~= "" then
      local a_str, b_str = token:match("^(%d+)%-(%d+)$")
      if a_str then
        local a, b = tonumber(a_str), tonumber(b_str)
        ---@cast a integer
        ---@cast b integer
        if a > b then
          a, b = b, a
        end
        local err = check_bounds(a) or check_bounds(b)
        if err then
          return nil, err
        end
        for n = a, b do
          set[n] = true
        end
      else
        local n_str = token:match("^(%d+)$")
        if not n_str then
          return nil, "range: invalid token '" .. token .. "'"
        end
        local n = tonumber(n_str)
        ---@cast n integer
        local err = check_bounds(n)
        if err then
          return nil, err
        end
        set[n] = true
      end
    end
  end

  local list = {}
  for n in pairs(set) do
    list[#list + 1] = n
  end
  table.sort(list)

  return list, nil
end

---@type Lib.Range
return M
