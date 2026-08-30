---@module 'lib.nvim.bindings.keymap.portability'
--- Can a terminal actually deliver this `lhs`?
---@description
--- A static classifier over the key notation itself. No terminal is queried,
--- nothing is probed, and that is the point: the question "can *this* key
--- reach Neovim" has no runtime answer, while "which class of key is at risk"
--- has a completely static one.
---
--- **Why not detect it at runtime.** Three separate walls, any one of them
--- sufficient:
---
---  1. *Neovim cannot press its own keys.* `nvim_feedkeys()`/`nvim_input()`
---     enter below the terminal's input decoder, so a self-test succeeds on a
---     terminal that could never have sent the key. There is no way to make a
---     terminal send a key to itself.
---  2. *The one real signal is not exposed.* Nvim queries the terminal for
---     "CSI u" support at startup (|tui-csiu|) and enables it or falls back to
---     modifyOtherKeys -- but the result reaches no Lua API. There is no
---     `keyprotocol` option in 0.12, and `g:termfeatures` carries only
---     `osc52`.
---  3. *It would be the wrong question anyway.* "This terminal supports the
---     protocol" is not "this key survives the trip". tmux and ssh rewrite
---     sequences in between, and the keyboard layout gets there first: on a
---     German layout AltGr *is* Ctrl+Alt, so `<C-M-q>` is consumed to produce
---     `@` and no key event is generated at all.
---
--- So classify the notation instead, and let the caller act on the class. The
--- fix for a fragile key is never detection -- it is binding a portable `lhs`
--- alongside it, which the registry has always supported (`default` takes a
--- list). See `bindings.audit.key_risks` for the lint that reports which
--- actions still lack one.
---
--- ```lua
--- local port = require("lib.nvim.bindings.keymap.portability")
--- port.classify("<leader>x")  --> "portable", ""
--- port.classify("<C-M-y>")    --> "common",   "Alt is sent as an ESC prefix ..."
--- port.classify("<C-CR>")     --> "fragile",  "Ctrl+CR is the same byte as CR ..."
--- ```
---@see lib.nvim.bindings.audit

local M = {}

--- How reliably a key reaches Neovim.
---
---  - `portable` -- a plain byte or a terminfo/xterm sequence. Arrives
---    everywhere; nothing to think about.
---  - `common` -- arrives in nearly every terminal, but through a mechanism
---    with a known off switch (Alt as an ESC prefix, Ctrl+Space as NUL) or
---    with a known ambiguity (`<C-i>` *is* `<Tab>`'s byte). Fine as the
---    everyday key, not fine as the *only* key.
---  - `fragile` -- needs an extended encoding ("CSI u"/modifyOtherKeys) or a
---    GUI. On a terminal without it, the key silently never arrives.
---@alias Lib.Keymap.Portability.Tier "portable"|"common"|"fragile"

---@internal
--- Notation letter -> modifier. `M` and `A` are the same modifier; `T`
--- (Meta) and `D` (Super/Command) exist in the notation but not in any
--- terminal encoding worth relying on.
local MODS = { C = "ctrl", S = "shift", M = "alt", A = "alt", D = "super", T = "meta" }

---@internal
--- Keys the terminal sends as their own escape sequence, modifiers included
--- (xterm's `CSI 1 ; <mod> <final>` family and the terminfo entries around
--- it). Ctrl or Alt on one of these is as deliverable as the bare key -- no
--- ESC prefix and no control byte is involved.
local SEQUENCED = {
  up = true,
  down = true,
  left = true,
  right = true,
  home = true,
  ["end"] = true,
  pageup = true,
  pagedown = true,
  pgup = true,
  pgdn = true,
  insert = true,
  del = true,
  delete = true,
  help = true,
  undo = true,
}

---@internal
--- Keys whose modified form is the *same byte* as the bare key. A terminal
--- cannot distinguish them without an extended encoding, so a mapping on the
--- modified form never fires (|tui-input|).
local AMBIGUOUS = {
  cr = true,
  ["return"] = true,
  enter = true,
  tab = true,
  bs = true,
  backspace = true,
  esc = true,
  nl = true,
}

---@internal
--- Punctuation that has a real C0 control code, so `<C-x>` on it is a byte
--- every terminal has always sent.
local CTRL_PUNCT = {
  ["@"] = true,
  ["["] = true,
  ["\\"] = true,
  ["]"] = true,
  ["^"] = true,
  ["_"] = true,
  ["?"] = true,
}

---@internal
--- The four Ctrl combinations that *do* arrive but land on another key's
--- byte: mapping them also remaps the key named here, unless the terminal
--- speaks an extended encoding.
local COLLIDES = { i = "<Tab>", m = "<CR>", j = "<NL>", ["["] = "<Esc>" }

---@internal
--- Names in `<...>` that are not a physical key: resolved at bind time, or
--- not a key at all.
local NOT_A_KEY =
  { leader = true, localleader = true, nop = true, sid = true, plug = true, cmd = true }

---@internal
local RANK = { portable = 1, common = 2, fragile = 3 }

---@internal
--- Split the inside of a `<...>` token into its modifiers and its base key.
---
--- Consumes `X-` prefixes only while `X` is a known modifier letter, which is
--- what makes `<A-->` (Alt plus minus) parse as `alt` + `-` rather than
--- eating the key itself.
---@param inner string
---@return table<string, boolean> mods, string base
local function split(inner)
  local mods, rest = {}, inner
  while true do
    local letter, tail = rest:match("^(%a)%-(.+)$")
    local mod = letter and MODS[letter:upper()]
    if not mod then
      break
    end
    mods[mod] = true
    rest = tail
  end
  return mods, rest
end

---@internal
--- Classify one `<...>` token.
---@param inner string
---@return Lib.Keymap.Portability.Tier tier, string reason
local function classify_token(inner)
  local mods, base = split(inner)
  local b = base:lower()

  if NOT_A_KEY[b] then
    return "portable", ""
  end

  -- Mouse events are not keyboard bytes. The terminal reports them on a
  -- channel of their own (X10/SGR mouse reporting), where the modifier state
  -- and the click count each have a field -- so `<C-LeftMouse>` and
  -- `<2-LeftMouse>` cost exactly what `<LeftMouse>` costs. Note that the
  -- click-count prefix also means `split()` never sees a modifier letter
  -- here, which is why this check reads the whole base rather than the mods.
  if
    b:find("mouse", 1, true)
    or b:find("scrollwheel", 1, true)
    or b:find("drag", 1, true)
    or b:find("release", 1, true)
  then
    return "portable", ""
  end

  if mods.super or mods.meta then
    return "fragile", ("%s has no terminal encoding at all (GUI only)"):format(inner)
  end

  local sequenced = SEQUENCED[b] or b:match("^f%d+$") ~= nil or b:match("^k%a") ~= nil
  local tier, reason = "portable", ""

  if mods.ctrl then
    if sequenced then
      tier = "portable"
    elseif AMBIGUOUS[b] then
      tier, reason = "fragile", ("Ctrl+%s is the same byte as %s"):format(base, base)
    elseif mods.shift then
      tier, reason = "fragile", ("Ctrl+Shift+%s is the same byte as Ctrl+%s"):format(base, base)
    elseif COLLIDES[b] then
      tier, reason =
        "common",
        ("<C-%s> is %s's byte: mapping it also remaps %s"):format(base, COLLIDES[b], COLLIDES[b])
    elseif b:match("^%a$") or CTRL_PUNCT[b] then
      tier = "portable"
    elseif b == "space" then
      tier, reason = "common", "Ctrl+Space is NUL, which not every terminal sends"
    else
      tier, reason = "fragile", ("no control byte exists for Ctrl+%s"):format(base)
    end
  elseif mods.shift then
    -- <S-Tab> is the one modified-ambiguous key with its own terminfo entry
    -- (kcbt / CSI Z), which is why back-tab works everywhere and <C-Tab>
    -- does not.
    if b == "tab" or sequenced then
      tier = "portable"
    elseif AMBIGUOUS[b] then
      tier, reason = "fragile", ("Shift+%s is the same byte as %s"):format(base, base)
    else
      tier = "portable" -- <S-a> is simply "A"
    end
  end

  if mods.alt and tier ~= "fragile" and not sequenced then
    tier = "common"
    if reason == "" then
      reason = 'Alt is sent as an ESC prefix: needs the terminal\'s "Alt sends Escape", '
        .. "and an AltGr layout can consume the combination before it becomes a key"
    end
  end

  return tier, reason
end

--- Classify a whole `lhs`, worst token first.
---
--- Literal characters between the `<...>` tokens are always deliverable and
--- are skipped; `<leader>x` is exactly as portable as whatever `mapleader`
--- happens to be.
---@param lhs string|nil
---@return Lib.Keymap.Portability.Tier tier, string reason # `reason` is "" for a portable key.
function M.classify(lhs)
  if type(lhs) ~= "string" or lhs == "" then
    return "portable", ""
  end

  local tier, reason, i = "portable", "", 1
  while i <= #lhs do
    local _, stop, inner = lhs:find("^<([^<>]+)>", i)
    if stop then
      local t, r = classify_token(inner)
      if RANK[t] > RANK[tier] then
        tier, reason = t, r
      end
      i = stop + 1
    else
      i = i + 1
    end
  end
  return tier, reason
end

--- Whether `lhs` reaches Neovim on any terminal, i.e. classifies `portable`.
---@param lhs string|nil
---@return boolean
function M.is_portable(lhs)
  return M.classify(lhs) == "portable"
end

return M
