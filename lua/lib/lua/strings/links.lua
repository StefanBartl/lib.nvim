---@module 'lib.lua.strings.links'
--- String helpers: URI decode, anchor normalization, simple scanners.

local M = {}

--- Minimal percent-decoding.
---@param s string
---@return string
function M.uri_decode(s)
  return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

--- Looser, Unicode-friendly anchor normalization:
--- - strip leading '#' (any count)
--- - lowercase (Lua's lower is fine; leaves umlauts as-is, which is OK)
--- - remove only a small ASCII punctuation set; keep non-ASCII letters
--- - collapse whitespace to '-'; trim leading/trailing '-'
---@param s string
---@return string
function M.normalize_anchor(s)
  local a = s:gsub("^%s*#*", "")
  a = a:lower()
  -- remove only characters that commonly don't appear in MD anchors
  a = a:gsub("[\"'()%[%]{}.:;!?*,]", "")
  -- spaces/tabs → '-'
  a = a:gsub("%s+", "-")
  -- collapse multiple '-'
  a = a:gsub("%-+", "-")
  -- trim '-'
  a = a:gsub("^%-+", ""):gsub("%-+$", "")
  return a
end

--- Generic scheme detector.
---@param s string
---@return boolean
function M.has_scheme(s)
  return s:match("^[a-zA-Z][a-zA-Z0-9+.-]*:") ~= nil
end

--- Typical web urls.
---@param s string
---@return boolean
function M.is_web_url(s)
  return s:match("^https?://") or s:match("^ftp://") or s:match("^mailto:")
end

--- Naked URL or <autolink> under cursor.
---@param line string
---@param col integer
---@return string|nil
function M.url_under_cursor(line, col)
  local s, e = line:find("<https?://[^%s>]+>")
  if s and col >= s and col <= e then
    return line:sub(s + 1, e - 1)
  end
  local i = 1
  while true do
    local ss, ee = line:find("https?://[%w%p]+", i)
    if not ss then break end
    if col >= ss and col <= ee then
      local url = line:sub(ss, ee):gsub("[%)%]%.,;:]+$", "")
      return url
    end
    i = ee + 1
  end
  return nil
end

return M
