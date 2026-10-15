---@module 'lib.nvim.contract.echo'
---@brief How a text of a client's request is shown in a refusal: short, valid UTF-8 and printable.
---@description
--- The names in a request (a method, a field, a parameter) are the client's. A refusal that repeats one must not
--- hand a control character, an invalid byte sequence or a megabyte of text to the terminal the message ends up on.
--- `contract.ops` and `contract.api` both echo client text, so the rule lives here once.

local json = require("lib.nvim.json.canonical")

local M = {}

---The longest echo, in characters.
---@type integer
M.MAX = 60

local ECHO_MAX = M.MAX

---A text of a request as it is echoed in a refusal: short (at most 60 characters, never cut inside one), valid UTF-8
---and printable. The names are the client's: a control character in one (ESC, BEL, a C1 control, a Unicode line
---separator) is written as an escape (`\x1b`, `\u009b`), so the message can be shown on a terminal as it is.
---@param text string
---@return string
function M.clip(text)
  -- 61 characters are 244 bytes at most: what lies behind them is never looked at (the request may be 256 KiB)
  if #text > 4 * (ECHO_MAX + 1) then
    text = text:sub(1, 4 * (ECHO_MAX + 1))
  end
  text = json.scrub_utf8(text)
  local keep, chars = 0, 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 0x80 or byte >= 0xC0 then -- not a continuation byte: a character starts here
      chars = chars + 1
      if chars == ECHO_MAX then
        keep = i - 1 -- the ellipsis takes the place of the last character
      elseif chars > ECHO_MAX then
        text = text:sub(1, keep) .. "…"
        break
      end
    end
  end
  local function escape(c)
    return ("\\x%02x"):format(c:byte())
  end
  text = text:gsub("[%z\1-\31\127]", escape)
  text = text:gsub("\194([\128-\159])", function(c)
    return ("\\u%04x"):format(c:byte())
  end)
  text = text:gsub("\226\128([\168\169])", function(c)
    return c == "\168" and "\\u2028" or "\\u2029"
  end)
  return text
end

---@type Lib.Contract.Echo
return M
