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

  local set = {}
  for token in (trimmed .. ","):gmatch("([^,]*),") do
    if token ~= "" then
      local a, b = token:match("^(%d+)%-(%d+)$")
      if a then
        a, b = tonumber(a), tonumber(b)
        if a > b then
          a, b = b, a
        end
        for n = a, b do
          set[n] = true
        end
      else
        local n = token:match("^(%d+)$")
        if not n then
          return nil, "range: invalid token '" .. token .. "'"
        end
        set[tonumber(n)] = true
      end
    end
  end

  local list = {}
  for n in pairs(set) do
    list[#list + 1] = n
  end
  table.sort(list)

  if opts.min or opts.max then
    for _, n in ipairs(list) do
      if opts.min and n < opts.min then
        return nil, "range: " .. n .. " is below min " .. opts.min
      end
      if opts.max and n > opts.max then
        return nil, "range: " .. n .. " is above max " .. opts.max
      end
    end
  end

  return list, nil
end

---@type Lib.Range
return M
