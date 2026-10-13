---@module 'lib.nvim.terminal.host'
--- Which terminal Neovim runs in, and what that means for escape sequences.
---
--- Detection only reads environment variables (a table that defaults to `vim.env`), so it is a
--- pure function that tests can feed. OSC 1337 has no capability query: a list of known
--- terminals is all there is, so `osc1337 = false` means "not known to", not "cannot".

local M = {}

---@param v any
---@return boolean
local function set(v)
  return type(v) == "string" and v ~= ""
end

--- Terminals that draw OSC 1337 (iTerm2 protocol), in detection order.
---@type { name: string, detect: fun(env: table): boolean }[]
local OSC1337 = {
  {
    name = "WezTerm",
    detect = function(env)
      return set(env.WEZTERM_EXECUTABLE) or set(env.WEZTERM_VERSION) or set(env.WEZTERM_PANE)
    end,
  },
  {
    name = "iTerm2",
    detect = function(env)
      return (env.TERM_PROGRAM or ""):lower():find("iterm", 1, true) ~= nil
        or (env.LC_TERMINAL or ""):lower():find("iterm", 1, true) ~= nil
    end,
  },
  {
    name = "Konsole",
    detect = function(env)
      return set(env.KONSOLE_VERSION)
    end,
  },
}

--- Terminals known not to draw OSC 1337 (named for messages only).
---@type { name: string, detect: fun(env: table): boolean }[]
local OTHER = {
  {
    name = "Kitty",
    detect = function(env)
      return set(env.KITTY_LISTEN_ON) or (env.TERM or ""):find("kitty", 1, true) ~= nil
    end,
  },
  {
    name = "Windows Terminal",
    detect = function(env)
      return set(env.WT_SESSION)
    end,
  },
}

--- Whether tmux sits between Neovim and the terminal.
---@param env? table Default `vim.env`
---@return boolean
function M.in_tmux(env)
  return set((env or vim.env).TMUX)
end

--- Describe the host terminal.
---@param env? table Environment to read (default `vim.env`)
---@return Lib.Terminal.Host
function M.detect(env)
  env = env or vim.env
  local res = { name = nil, osc1337 = false, in_tmux = M.in_tmux(env), hint = nil }
  for _, term in ipairs(OSC1337) do
    if term.detect(env) then
      res.name, res.osc1337 = term.name, true
      break
    end
  end
  if not res.name then
    for _, term in ipairs(OTHER) do
      if term.detect(env) then
        res.name = term.name
        break
      end
    end
  end
  if res.in_tmux then
    -- tmux forwards a sequence only in its passthrough envelope and with allow-passthrough.
    res.hint = "under tmux: `set -g allow-passthrough on` is required, or nothing arrives"
  end
  return res
end

return M
