---@module 'lib.lua.strings.patterns'
--- Pattern utilities: escaping, plain find/replace, surrounding helpers.

---@type LibStringsPatterns
local P = {}

---@nodiscard
---@param s string
---@return string
function P.escape_lua_magic(s)
  -- Escape Lua pattern magic characters
  return (s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

---@nodiscard
---@param s string
---@param needle string
---@return integer|nil start
---@return integer|nil finish
function P.find_plain(s, needle)
  local a, b = s:find(needle, 1, true)
  if a then
    return a, b
  end
  return nil, nil
end

---@nodiscard
---@param s string
---@param from string
---@param to string
---@return string
function P.replace_plain(s, from, to)
  if from == "" then
    return s
  end
  local res, i = {}, 1
  while true do
    local a, b = s:find(from, i, true)
    if not a then
      res[#res + 1] = s:sub(i)
      break
    end
    res[#res + 1] = s:sub(i, a - 1)
    res[#res + 1] = to
    i = b + 1
  end
  return table.concat(res)
end

---@nodiscard
---@param s string
---@param left string
---@param right string
---@return string
function P.surround(s, left, right)
  return left .. s .. right
end

---Strip ANSI escape sequences from a string: SGR color codes (`\27[...m`),
---OSC sequences terminated by BEL (`\27]...\7`, e.g. terminal title-setting),
---stray null bytes, and a broader CSI-like catch-all for sequences the first
---two patterns miss. Upstreamed from mdview.nvim's adapter/log.lua, whose
---version covered all of these against raw subprocess relay output — this
---module's previous single-pattern version only handled SGR codes.
---@nodiscard
---@param s string
---@return string
function P.strip_ansi(s)
  return (
    s:gsub("%z", "")
      :gsub("\27%[[%d;]*m", "")
      :gsub("\27%]%d+;.-\7", "")
      :gsub("\27%[?%d+;?%d*%p?", "")
  )
end

return P
