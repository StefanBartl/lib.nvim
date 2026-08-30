-- TESTS/keymap_portability_spec.lua — lib.nvim.bindings.keymap.portability
-- and the bindings.audit lint built on it.

return function(H)
  local eq, ok = H.eq, H.ok

  local port = require("lib.nvim.bindings.keymap.portability")
  local keymap = require("lib.nvim.bindings.keymap")
  local audit = require("lib.nvim.bindings.audit")

  local function tier(lhs)
    local t = port.classify(lhs)
    return t
  end

  -- ------------------------------------------------------------- portable

  eq(tier("<leader>x"), "portable", "a leader key resolves at bind time")
  eq(tier("gF"), "portable", "plain literal keys")
  eq(tier("]k"), "portable", "bracket pairs")
  eq(tier("<C-y>"), "portable", "Ctrl+letter is a C0 control byte")
  eq(tier("<C-\\>"), "portable", "Ctrl+backslash is 0x1C, a real control byte")
  eq(tier("<C-@>"), "portable", "Ctrl+@ is NUL, a real control byte")
  eq(tier("<S-a>"), "portable", "Shift+letter is simply the uppercase character")
  eq(tier("<Plug>(foo-bar)"), "portable", "<Plug> is not a physical key")
  eq(tier("<F5>"), "portable", "function keys have their own sequence")
  eq(tier(nil), "portable", "nil is not a risk")

  -- Modified navigation keys travel as xterm's own `CSI 1;<mod><final>`
  -- sequence -- no ESC prefix and no control byte, so a modifier costs
  -- nothing here. This is why <A-Right> is safe where <A-c> is not.
  eq(tier("<A-Right>"), "portable", "Alt+arrow is an xterm sequence, not an ESC prefix")
  eq(tier("<C-Up>"), "portable", "Ctrl+arrow likewise")
  eq(tier("<S-Tab>"), "portable", "back-tab has its own terminfo entry (kcbt)")

  -- Mouse events travel on the terminal's own reporting channel, where the
  -- modifier state and the click count each have a field -- no control byte
  -- is involved, so a modifier costs nothing.
  eq(tier("<LeftMouse>"), "portable", "a bare mouse event")
  eq(tier("<C-LeftMouse>"), "portable", "Ctrl+click is a mouse event, not a control byte")
  eq(tier("<2-LeftMouse>"), "portable", "a click count is not a modifier letter")
  eq(tier("<C-ScrollWheelDown>"), "portable", "modified scroll wheel likewise")
  eq(tier("<LeftDrag>"), "portable", "drag events too")

  -- --------------------------------------------------------------- common

  eq(tier("<A-c>"), "common", "Alt+letter rides an ESC prefix")
  eq(tier("<C-M-y>"), "common", "Ctrl+Alt+letter is ESC plus a control byte")
  eq(tier("<A-->"), "common", "Alt+punctuation parses as alt + '-', not as a stray modifier")
  eq(tier("<C-Space>"), "common", "Ctrl+Space is NUL, which not every terminal sends")
  eq(tier("<C-i>"), "common", "<C-i> arrives, but on <Tab>'s byte")
  eq(tier("<C-[>"), "common", "<C-[> arrives, but on <Esc>'s byte")

  local _, why = port.classify("<C-M-y>")
  ok(why:find("AltGr", 1, true), "the Alt reason names the layout trap, not just the terminal")

  -- -------------------------------------------------------------- fragile

  eq(tier("<C-#>"), "fragile", "no control byte exists for Ctrl+#")
  eq(tier("<C-1>"), "fragile", "digits have no control byte either")
  eq(tier("<C-CR>"), "fragile", "Ctrl+CR collides with CR")
  eq(tier("<C-Tab>"), "fragile", "Ctrl+Tab collides with Tab")
  eq(tier("<C-S-x>"), "fragile", "Ctrl+Shift+letter is Ctrl+letter's byte")
  eq(tier("<C-A-S-p>"), "fragile", "Alt cannot rescue a combination that is already ambiguous")
  eq(tier("<D-s>"), "fragile", "Super/Command exists only in a GUI")

  -- The worst token in a sequence decides.
  eq(tier("<leader><C-#>"), "fragile", "a portable prefix does not redeem a fragile key")

  eq(port.is_portable("<leader>x"), true, "is_portable: portable")
  eq(port.is_portable("<C-M-y>"), false, "is_portable: common is not portable")

  -- ------------------------------------------------------ the audit lint

  -- Three actions: one fragile with no way out, one fragile *with* a
  -- portable alias, one plain. Only the first should be reported -- the
  -- alias is the entire fix this lint exists to ask for.
  keymap.register("portspec", {
    prefix = "<Plug>(portspec-",
    actions = {
      naked = { default = "<C-#>", rhs = function() end, desc = "fragile, no alias" },
      aliased = {
        default = { "<C-#>", "<Plug>(portspec-aliased)" },
        rhs = function() end,
        desc = "fragile, with a portable alias",
      },
      plain = { default = "<Plug>(portspec-plain)", rhs = function() end, desc = "portable" },
    },
  })

  local risks = {}
  for _, r in ipairs(audit.key_risks(nil)) do
    if r.surface == "portspec" then
      risks[r.name] = r
    end
  end

  ok(risks.naked, "key_risks reports an action whose only key is fragile")
  eq(risks.naked.best, "fragile", "and reports how bad its best key is")
  eq(#risks.naked.keys, 1, "with the key that caused it")
  eq(risks.aliased, nil, "an action with a portable alias is NOT reported")
  eq(risks.plain, nil, "a portable action is not reported")

  local lines = table.concat(audit.key_risk_lines(nil), "\n")
  ok(lines:find("portspec.naked", 1, true), "the printable report names the action")
  ok(lines:find("no control byte", 1, true), "and says why the key cannot arrive")
  ok(lines:find("`default` list", 1, true), "and names the fix")

  keymap.forget("portspec")
end
