---@module 'lib.nvim.terminal.capabilities'
--- What the host terminal can draw or understand, from environment variables; cached for the session, with
--- one warning per missing capability instead of one per attempt.
---
--- Built for plugins that send terminal-dependent escape sequences (inline images, hyperlinks, true colour):
--- none of these has a reliable capability query a plugin could ask at runtime, so the answer is a heuristic
--- over `$TERM`, `$TERM_PROGRAM`, `$COLORTERM` and the terminal-specific variables, built on
--- `lib.nvim.terminal.host`. An answer is "this terminal is known to", never a guarantee: over SSH the
--- terminal-specific variables are usually not forwarded (a capable terminal reads as `false`), and under
--- tmux they ARE inherited (`true`, but graphics only arrive with `allow-passthrough on`: see `host.in_tmux`
--- and `host.hint` in the result of `detect`).
---
--- Generalised from `images.nvim`'s terminal check.
---
--- ```lua
--- local caps = require("lib.nvim.terminal.capabilities")
---
--- if caps.require("kitty_graphics", { feature = "inline images" }) then
---   -- send the sequence; otherwise ONE warning was shown for the whole session, then silence
--- end
---
--- caps.supports("truecolor")        --> boolean, cached
--- caps.detect({ TERM = "foot" })    --> pure: capabilities for the given environment (tests)
--- ```

local M = {}

---@alias Lib.Terminal.CapabilityName "kitty_graphics"|"osc1337_images"|"sixel"|"truecolor"

---@class Lib.Terminal.Capabilities
---@field kitty_graphics boolean  # Kitty graphics protocol (Kitty, WezTerm, Ghostty, Konsole).
---@field osc1337_images boolean  # iTerm2 inline-image protocol (WezTerm, iTerm2, Konsole).
---@field sixel boolean           # Sixel graphics (foot, mlterm, WezTerm, iTerm2, a `$TERM` naming sixel).
---@field truecolor boolean       # 24-bit colour (`$COLORTERM` truecolor/24bit).
---@field host Lib.Terminal.Host  # The terminal that was recognised, and whether tmux is in between.

---@type Lib.Terminal.CapabilityName[]
local NAMES = { "kitty_graphics", "osc1337_images", "sixel", "truecolor" }

---@param v any
---@return string
local function lower(v)
  return type(v) == "string" and v:lower() or ""
end

---@param v any
---@return boolean
local function set(v)
  return type(v) == "string" and v ~= ""
end

---Capabilities of the terminal described by `env` (default `vim.env`). Pure: nothing is cached.
---@param env? table
---@return Lib.Terminal.Capabilities
function M.detect(env)
  env = env or vim.env
  local host = require("lib.nvim.terminal.host").detect(env)
  local term, program = lower(env.TERM), lower(env.TERM_PROGRAM)
  local name = host.name

  local kitty = name == "Kitty"
    or set(env.KITTY_WINDOW_ID)
    or term:find("kitty", 1, true) ~= nil
    or program == "ghostty"
    or set(env.GHOSTTY_RESOURCES_DIR)
    or term:find("ghostty", 1, true) ~= nil

  local sixel = term:find("sixel", 1, true) ~= nil
    or term:find("foot", 1, true) == 1
    or term:find("mlterm", 1, true) ~= nil
    or name == "WezTerm"
    or name == "iTerm2"

  local colorterm = lower(env.COLORTERM)
  return {
    kitty_graphics = (kitty or name == "WezTerm" or name == "Konsole") and true or false,
    osc1337_images = host.osc1337 == true,
    sixel = sixel,
    truecolor = colorterm == "truecolor" or colorterm == "24bit",
    host = host,
  }
end

---@type Lib.Terminal.Capabilities|nil
local cached = nil
---@type table<string, true>
local warned = {}

---@return Lib.Terminal.Capabilities
local function session()
  if not cached then
    cached = M.detect()
  end
  return cached
end

---The capability names, for a settings UI or a health report.
---@return Lib.Terminal.CapabilityName[]
function M.names()
  return vim.list_extend({}, NAMES)
end

---Whether the terminal is known to have `name`. Detected once per session, then cached.
---@param name Lib.Terminal.CapabilityName
---@return boolean
function M.supports(name)
  if not vim.tbl_contains(NAMES, name) then
    error(("lib.nvim.terminal.capabilities: unknown capability %s"):format(vim.inspect(name)), 2)
  end
  return session()[name] == true
end

---@class Lib.Terminal.RequireOpts
---@field feature? string                   # What needs it, for the warning ("inline images").
---@field notify? fun(msg: string)          # Warning sink (default: `lib.nvim.notify` WARN).

---`supports(name)`, plus exactly ONE warning per missing capability and `opts.feature` for the whole session:
---a plugin that tries to draw on every cursor move would otherwise repeat it a hundred times, while a second
---plugin (or feature) that also needs it still tells its own user once.
---@param name Lib.Terminal.CapabilityName
---@param opts? Lib.Terminal.RequireOpts
---@return boolean
function M.require(name, opts)
  if M.supports(name) then
    return true
  end
  opts = opts or {}
  -- per capability AND feature: two plugins missing the same capability each tell their user once, one
  -- feature retrying on every cursor move stays silent after the first
  local mark = name .. "|" .. (opts.feature or "")
  if warned[mark] then
    return false
  end
  warned[mark] = true
  local host = session().host
  local msg = ("%s needs %s, which this terminal is not known to support (terminal: %s)"):format(
    opts.feature or "this feature",
    name,
    host.name or "unknown"
  )
  if host.hint then
    msg = msg .. "; " .. host.hint
  end
  if opts.notify then
    opts.notify(msg)
  else
    require("lib.nvim.notify").create("[lib.nvim.terminal]").warn(msg)
  end
  return false
end

---Forget the cached detection and the "already warned" marks (tests, or after `$TERM` changed).
---@return nil
function M.reset()
  cached = nil
  warned = {}
end

return M
