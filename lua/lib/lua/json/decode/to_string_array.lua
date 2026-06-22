---@module 'lib.lua.json.decode.to_string_array'
--- Wrapper utilities to coerce various preset outputs into a string array
--- and to call downstream presets that expect string[].

local M = {}

---@param v any
---@return boolean
function M.is_array_like(v)
  -- Check for simple array-like table: contiguous positive integer keys starting at 1
  if type(v) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(v) do
    i = i + 1
    if v[i] == nil then
      return false
    end
  end
  return true
end

---@param tbl table
---@return string[] coerced
function M.table_to_string_array(tbl)
  -- Convert numeric array-like table elements to strings.
  -- If table is not array-like, fall back to serializing top-level values
  -- with key ordering stable for common cases.
  if M.is_array_like(tbl) then
    local out = {} ---@type string[]
    for i = 1, #tbl do
      out[i] = tostring(tbl[i])
    end
    return out
  end

  -- Non-array-like table: produce one string per key in sorted order
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  local out = {} ---@type string[]
  for i, k in ipairs(keys) do
    -- For nested tables, use vim.inspect to get readable representation.
    -- Caller can replace vim.inspect with a custom serializer if needed.
    local v = tbl[k]
    if type(v) == "table" then
      out[i] = tostring(k) .. ": " .. vim.inspect(v)
    else
      out[i] = tostring(k) .. ": " .. tostring(v)
    end
  end
  return out
end

---@param v any
---@return string[] coerced
function M.ensure_string_array(v)
  -- If input is already a table-of-strings, return it (ensuring tostring conversion).
  if type(v) == "table" then
    return M.table_to_string_array(v)
  end

  -- If input is a string, split on newlines into lines
  if type(v) == "string" then
    -- Use vim.split to preserve display widths consistent with Neovim
    local lines = vim.split(v, "\n", { plain = true })
    -- Ensure each entry is a string
    for i = 1, #lines do
      lines[i] = tostring(lines[i])
    end
    return lines ---@type string[]
  end

  -- For numbers or booleans etc., return a single-element array with tostring
  return { tostring(v) } ---@type string[]
end

---@type Lib.JSON.Decode.ToStringArray
return M
