---@module 'lib.lua.strings.core'
--- String helpers: trimming, splitting, joining, casing, padding, indenting.

---@type LibStringsCore
local S = {}

---@nodiscard
---@param s any
---@return string
function S.trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@nodiscard
---@param s string
---@param prefix string
---@return boolean
function S.starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

---@nodiscard
---@param s string
---@param suffix string
---@return boolean
function S.ends_with(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

---@nodiscard
---@param s string
---@param needle string
---@return boolean
function S.contains(s, needle)
  return s:find(needle, 1, true) ~= nil
end

---@nodiscard
---@param s string
---@param sep string
---@return string[]
function S.split(s, sep)
  if sep == "" then
    return { s }
  end
  ---@type string[]
  local out = {}
  local i = 1
  while true do
    local a, b = s:find(sep, i, true)
    if not a then
      out[#out + 1] = s:sub(i)
      break
    end
    out[#out + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  return out
end

---@nodiscard
---@param parts string[]
---@param sep string
---@return string
function S.join(parts, sep)
  return table.concat(parts, sep)
end

---@nodiscard
---@param s string
---@param from string
---@param to string
---@return string
function S.replace_all(s, from, to)
  if from == "" then
    return s
  end
  local res = {}
  local i = 1
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
---@return string|nil
function S.normalize_ws(s)
  local r, _
  (s:gsub("%s+", " ")):gsub("^%s+", ""):gsub("%s+$", "")
  return r
end

---@nodiscard
---@param s string
---@return string
function S.capitalize(s)
  if s == "" then
    return s
  end
  return s:sub(1, 1):upper() .. s:sub(2)
end

---@nodiscard
---@param s string
---@return string
function S.uncapitalize(s)
  if s == "" then
    return s
  end
  return s:sub(1, 1):lower() .. s:sub(2)
end

---@nodiscard
---@param s string
---@return string
function S.slugify(s)
  local t = s:lower()
  t = (t:gsub("[^%w%s%-_]", ""))
  t = (t:gsub("%s+", "-"))
  t = (t:gsub("%-+", "-"))
  return t
end

---@nodiscard
---@param s string
---@return string
function S.kebab_case(s)
  local t = s
  t = (t:gsub("%f[%w]%u", "-%1")) -- FooBar -> Foo-Bar
  t = (t:gsub("[%s_]+", "-")) -- space/underscore -> dash
  t = t:lower()
  t = (t:gsub("%-+", "-"))
  t = (t:gsub("^%-", "")):gsub("%-$", "")
  return t
end

---@nodiscard
---@param s string
---@return string
function S.snake_case(s)
  local t = s
  t = (t:gsub("%f[%w]%u", "_%1"))
  t = (t:gsub("[%s%-]+", "_"))
  t = t:lower()
  t = (t:gsub("_+", "_"))
  t = (t:gsub("^_", "")):gsub("_$", "")
  return t
end

---@nodiscard
---@param s string
---@return string
function S.camel_case(s)
  local words = {}
  for w in s:gmatch("[^%s%-%_]+") do
    words[#words + 1] = w:lower()
  end
  if #words == 0 then
    return ""
  end
  local head = words[1]
  for i = 2, #words do
    local w = words[i]
    head = head .. w:sub(1, 1):upper() .. w:sub(2)
  end
  return head
end

---@nodiscard
---@param s string
---@param width integer
---@return string
function S.pad_start(s, width)
  if #s >= width then
    return s
  end
  return string.rep(" ", width - #s) .. s
end

---@nodiscard
---@param s string
---@param width integer
---@return string
function S.pad_end(s, width)
  if #s >= width then
    return s
  end
  return s .. string.rep(" ", width - #s)
end

---@nodiscard
---@param s string
---@param width integer
---@return string
function S.pad_center(s, width)
  if #s >= width then
    return s
  end
  local total = width - #s
  local left = math.floor(total / 2)
  local right = total - left
  return string.rep(" ", left) .. s .. string.rep(" ", right)
end

---@nodiscard
---@param s string
---@param n integer
---@return string
function S.indent(s, n)
  local pad = string.rep(" ", n)
  return pad .. (s:gsub("\n", "\n" .. pad))
end

---@nodiscard
---@param s string
---@return string
function S.dedent(s)
  ---@type number
  local min = math.huge

  for line in (s .. "\n"):gmatch("(.-)\n") do
    local _, spaces = line:find("^[ ]*")
    local count = spaces and #spaces or 0
    if line:find("%S") then
      min = math.min(min, count)
    end
  end

  if min == math.huge or min == 0 then
    return s
  end

  return (s:gsub("\n[ ]{" .. min .. "}", "\n"):gsub("^[ ]{" .. min .. "}", ""))
end

---@nodiscard
---@param s any
---@return boolean
function S.is_empty_or_space(s)
  if type(s) ~= "string" then
    return true
  end
  return s:find("%S") == nil
end

---Count lines in a string
---@param s string
---@return integer
function S.count_lines(s)
  if s == "" then return 0 end
  local count = 0
  for _ in s:gmatch("[^\n]+") do
    count = count + 1
  end
  return count
end

return S
