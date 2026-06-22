---@module 'lib.lua.strings.remove_prefix'
--- Remove the literal prefixes "vim.api.", "vim.fn." and "vim.uv.", etc... from a string.

---@type string[]  -- list of literal prefixes to remove
local default_blacklist = {
  [1] = "vim.api.",
  [2] = "vim.fn.",
  [3] = "vim.uv.",
}

--- Escape Lua pattern magic characters so the input becomes a safe literal pattern.
--- This function escapes: ^ $ ( ) % . [ ] * + - ?
--- @param s string
--- @return string
local function escape_lua_pattern(s)
  -- Escape each lua pattern magic character with a leading '%'
  -- List tuned to Lua pattern special chars.
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- Remove all occurrences of any prefix from the blacklist in a single string.
--- Performs literal (escaped) replacements in a loop to avoid relying on non-existing
--- alternation in Lua patterns.
--- @param s string
--- @param list table
--- @return string [number, string]
return function(s, list)
  if type(s) ~= "string" then
    return s
  end

  if type(list) ~= "table" then
    return s
  end

  list = list and list or default_blacklist

  -- iterate over blacklist entries and remove literal occurrences
  local out = s
  for _, prefix in ipairs(list) do
    if type(prefix) == "string" and prefix ~= "" then
      -- escape prefix for safe usage in gsub pattern
      local pat = escape_lua_pattern(prefix)
      -- remove all occurrences (no count argument): replace literal prefix with empty string
      out = out:gsub(pat, "")
    end
  end

  return out
end
