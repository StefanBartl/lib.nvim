---@module 'lib.lua.strings.encoding'
--- Percent-encoding (URL) and base64 encode/decode, pure Lua.

local M = {}

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

---Percent-encode a string for use in a URL (unreserved chars per RFC 3986
---pass through unescaped: A-Z a-z 0-9 - _ . ~).
---@param str string
---@return string
function M.url_encode(str)
  return (str:gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

---Decode a percent-encoded string.
---@param str string
---@return string
function M.url_decode(str)
  return (str:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

---Base64-encode a byte string.
---@param data string
---@return string
function M.base64_encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local b1, b2, b3 = data:byte(i, i + 2)
    b2 = b2 or 0
    b3 = b3 or 0
    local n = b1 * 0x10000 + b2 * 0x100 + b3
    local c1 = math.floor(n / 0x40000) % 0x40
    local c2 = math.floor(n / 0x1000) % 0x40
    local c3 = math.floor(n / 0x40) % 0x40
    local c4 = n % 0x40
    local chars = {
      B64_CHARS:sub(c1 + 1, c1 + 1),
      B64_CHARS:sub(c2 + 1, c2 + 1),
      (i + 1 <= #data) and B64_CHARS:sub(c3 + 1, c3 + 1) or "=",
      (i + 2 <= #data) and B64_CHARS:sub(c4 + 1, c4 + 1) or "=",
    }
    out[#out + 1] = table.concat(chars)
  end
  return table.concat(out)
end

---Decode a base64 string back to raw bytes.
---@param data string
---@return string
function M.base64_decode(data)
  data = data:gsub("[^%w%+%/%=]", "")
  local lookup = {}
  for i = 1, #B64_CHARS do
    lookup[B64_CHARS:sub(i, i)] = i - 1
  end
  local out = {}
  for i = 1, #data, 4 do
    local c1 = lookup[data:sub(i, i)] or 0
    local c2 = lookup[data:sub(i + 1, i + 1)] or 0
    local s3 = data:sub(i + 2, i + 2)
    local s4 = data:sub(i + 3, i + 3)
    local c3 = lookup[s3] or 0
    local c4 = lookup[s4] or 0
    local n = c1 * 0x40000 + c2 * 0x1000 + c3 * 0x40 + c4
    local b1 = math.floor(n / 0x10000) % 0x100
    local b2 = math.floor(n / 0x100) % 0x100
    local b3 = n % 0x100
    out[#out + 1] = string.char(b1)
    if s3 ~= "" and s3 ~= "=" then
      out[#out + 1] = string.char(b2)
    end
    if s4 ~= "" and s4 ~= "=" then
      out[#out + 1] = string.char(b3)
    end
  end
  return table.concat(out)
end

return M
