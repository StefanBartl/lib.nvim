---@module 'lib.lua.tables.with'
--- Utility to merge two option tables. Returns a new table if base is nil.

---@param base table|nil
---@param extra table|nil
---@return table
return function(base, extra)
  if not extra then
    return base or {}
  end
  if not base then
    local out = {}
    for k, v in pairs(extra) do
      out[k] = v
    end
    return out
  end
  for k, v in pairs(extra) do
    base[k] = v
  end
  return base
end
