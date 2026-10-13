---@module 'lib.nvim.terminal.osc'
--- Builders and the one writer for the escape sequences a plugin sends to the host terminal.
---
--- Text that came from a buffer, a branch name or a file name must not be spliced into a
--- sequence as is: a control character ends it early or starts another. `sanitize` makes text
--- safe to show, `user_var` validates the name and base64-encodes the value.
---
--- Inside tmux a sequence reaches the outer terminal only in tmux's DCS passthrough envelope
--- (`ESC P tmux ; <seq with every ESC doubled> ESC \`) and with `allow-passthrough on`.
--- `wrap_tmux` builds the envelope. `send` writes through `nvim_ui_send` (Neovim 0.12+): the
--- parts of one picture must go out in ONE call, or Neovim's own redraw can slip in between.

local M = {}

local ESC = "\27"
local BEL = "\7"

--- Make text safe to show: every control character (C0, DEL) becomes `?`, then the result is
--- cut to at most `max` bytes without splitting a UTF-8 character.
---@param s any
---@param max? integer Byte limit (default 200)
---@return string
function M.sanitize(s, max)
  max = max or 200
  if type(s) ~= "string" then
    s = tostring(s == nil and "" or s)
  end
  s = s:gsub("[%z\1-\31\127]", "?")
  if #s <= max then
    return s
  end
  local cut = max
  -- Step back over UTF-8 continuation bytes (10xxxxxx) so a character is not cut in half.
  while cut > 0 do
    local b = s:byte(cut + 1)
    if b and b >= 0x80 and b < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return s:sub(1, cut)
end

--- One `OSC 1337 ; SetUserVar=<name>=<base64>` sequence (WezTerm, iTerm2).
---@param name string `[A-Za-z0-9_]+`
---@param value string Any bytes; encoded as base64
---@return string|nil sequence
---@return string|nil err
function M.user_var(name, value)
  if type(name) ~= "string" or not name:find("^[%w_]+$") then
    return nil, "invalid user-var name"
  end
  if type(value) ~= "string" then
    return nil, "user-var value must be a string"
  end
  return ("%s]1337;SetUserVar=%s=%s%s"):format(ESC, name, vim.base64.encode(value), BEL), nil
end

--- Wrap a sequence in tmux's passthrough envelope.
---@param seq string
---@return string
function M.wrap_tmux(seq)
  return ESC .. "Ptmux;" .. seq:gsub(ESC, ESC .. ESC) .. ESC .. "\\"
end

--- Wrap `seq` when tmux is in between.
---@param seq string
---@param in_tmux? boolean Default: whether `$TMUX` is set
---@return string
function M.wrap(seq, in_tmux)
  if in_tmux == nil then
    in_tmux = require("lib.nvim.terminal.host").in_tmux()
  end
  return in_tmux and M.wrap_tmux(seq) or seq
end

--- Whether `send` can write at all (`nvim_ui_send`, Neovim 0.12+).
---@return boolean
function M.available()
  return type(vim.api.nvim_ui_send) == "function"
end

--- Write `payload` to the host terminal in one call.
---@param payload string
---@return boolean ok
---@return string|nil err
function M.send(payload)
  if not M.available() then
    return false, "nvim_ui_send is missing (needs Neovim 0.12+)"
  end
  local ok, err = pcall(vim.api.nvim_ui_send, payload)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M
