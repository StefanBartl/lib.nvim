---@module 'lib.nvim.bindings.usercmd.composer.tokens'
--- Quote-aware tokenizer for verbs that set `spec.quotes = true`.
---
--- Neovim hands a `-nargs=*` command its arguments split on blanks only, so
--- `:Replace "foo bar" baz` arrives in `fargs` as `"foo`, `bar"`, `baz`. A verb
--- that bypasses `fargs` and reads `opts.args` with a tokenizer of its own
--- (replacer.nvim's `:Replace` / `:Surround`) sees `foo bar`, `baz` -- and the
--- help float and `<Tab>` completion, which only ever saw the blank split,
--- would count one slot too many. `spec.quotes = true` tells them to cut the
--- line the way such a verb does:
---
---   * a token that **starts** with `'` or `"` runs to the matching quote,
---     blanks inside included, and ends there (`"a b"c` is two tokens); a quote
---     in the middle of a token is an ordinary character;
---   * `\"`, `\'`, `\\` and `\<blank>` are escapes, inside and outside quotes;
---     any other backslash stays (`C:\Users\x` is read as typed);
---   * an unterminated quote runs to the end of the line.
---
--- Pure -- no registry, no editor state.

local M = {}

--- What a backslash can escape: the quotes, the backslash and a blank.
local ESCAPABLE = [=[["'\%s]]=]

---@class Lib.UserCmd.Composer.Token
---@field raw   string  # as typed, quotes and escapes included
---@field value string  # what the verb's tokenizer makes of it (`"a b"` -> `a b`)

---@internal
--- Read one token starting at byte `i` of `text`.
---@param text string
---@param i integer
---@return Lib.UserCmd.Composer.Token token
---@return integer next   # first byte after the token
---@return boolean unclosed  # started with a quote that was never closed
local function read(text, i)
  local n = #text
  local buf = {}
  local quote = text:sub(i, i)
  local quoted = quote == '"' or quote == "'"
  local j = quoted and i + 1 or i
  while j <= n do
    local ch = text:sub(j, j)
    if ch == "\\" and j < n and text:sub(j + 1, j + 1):match(ESCAPABLE) then
      buf[#buf + 1] = text:sub(j + 1, j + 1)
      j = j + 2
    elseif quoted and ch == quote then
      j = j + 1
      return { raw = text:sub(i, j - 1), value = table.concat(buf) }, j, false
    elseif not quoted and ch:match("%s") then
      break
    else
      buf[#buf + 1] = ch
      j = j + 1
    end
  end
  -- The text ended before the closing quote (an unquoted token just ends here).
  return { raw = text:sub(i, j - 1), value = table.concat(buf) }, j, quoted
end

--- Split `text` (the arguments after the command word) into tokens.
---
--- `open` is true when the last token touches the end of the text: it is still
--- being typed -- also a quoted token whose closing quote is the last
--- character, because the next keystroke may continue it. `unclosed` is true
--- when that last token sits inside a quote that has not been closed yet.
---@param text string
---@return Lib.UserCmd.Composer.Token[] tokens
---@return boolean open
---@return boolean unclosed
function M.split_quoted(text)
  local out, i, n = {}, 1, #text
  local open, unclosed = false, false
  while i <= n do
    if text:sub(i, i):match("%s") then
      i = i + 1
    else
      local token, nxt, unterminated = read(text, i)
      out[#out + 1] = token
      i = nxt
      open, unclosed = i > n, unterminated
    end
  end
  return out, open, unclosed
end

return M
