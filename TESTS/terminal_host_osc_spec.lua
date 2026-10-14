-- TESTS/terminal_host_osc_spec.lua — lib.nvim.terminal.host, lib.nvim.terminal.osc

return function(H)
  local eq, ok = H.eq, H.ok
  local host = require("lib.nvim.terminal.host")
  local osc = require("lib.nvim.terminal.osc")

  -- ------------------------------------------------------------------ host
  local none = host.detect({})
  eq(none.name, nil, "host: an empty environment is unknown")
  eq(none.osc1337, false, "host: unknown does not claim OSC 1337")
  eq(none.in_tmux, false, "host: no $TMUX, not in tmux")
  eq(none.hint, nil, "host: no hint outside tmux")

  eq(host.detect({ WEZTERM_PANE = "3" }).name, "WezTerm", "host: $WEZTERM_PANE is WezTerm")
  eq(host.detect({ WEZTERM_VERSION = "20240203" }).osc1337, true, "host: WezTerm draws OSC 1337")
  eq(host.detect({ WEZTERM_PANE = "" }).name, nil, "host: an empty variable does not count")
  eq(host.detect({ TERM_PROGRAM = "iTerm.app" }).name, "iTerm2", "host: TERM_PROGRAM iTerm")
  eq(host.detect({ LC_TERMINAL = "iTerm2" }).name, "iTerm2", "host: LC_TERMINAL iTerm")
  eq(host.detect({ KONSOLE_VERSION = "230800" }).name, "Konsole", "host: Konsole")

  local kitty = host.detect({ TERM = "xterm-kitty" })
  eq(kitty.name, "Kitty", "host: Kitty by $TERM")
  eq(kitty.osc1337, false, "host: Kitty is named but does not draw OSC 1337")
  eq(
    host.detect({ KITTY_LISTEN_ON = "unix:/tmp/k" }).name,
    "Kitty",
    "host: Kitty by $KITTY_LISTEN_ON"
  )
  local wt = host.detect({ WT_SESSION = "abc" })
  eq(wt.name, "Windows Terminal", "host: Windows Terminal")
  eq(wt.osc1337, false, "host: Windows Terminal is not known to draw OSC 1337")

  eq(
    host.detect({ WEZTERM_PANE = "1", TERM = "xterm-kitty" }).name,
    "WezTerm",
    "host: OSC 1337 terminals win"
  )

  local tm = host.detect({ WEZTERM_PANE = "1", TMUX = "/tmp/tmux-1/default,1,0" })
  eq(tm.in_tmux, true, "host: $TMUX means tmux")
  eq(tm.name, "WezTerm", "host: tmux keeps the outer terminal's name")
  ok(tm.hint and tm.hint:find("allow-passthrough", 1, true), "host: the tmux hint names the option")
  eq(host.in_tmux({ TMUX = "" }), false, "host.in_tmux: empty is not tmux")

  -- ------------------------------------------------------------------- osc
  eq(osc.sanitize("a\27[31mb\0c\127"), "a?[31mb?c?", "osc.sanitize: control characters become ?")
  eq(osc.sanitize(nil), "", "osc.sanitize: nil is empty")
  eq(osc.sanitize(12), "12", "osc.sanitize: a number is shown")
  eq(#osc.sanitize(string.rep("x", 500)), 200, "osc.sanitize: default limit 200")
  local euro = "a" .. string.rep("\226\130\172", 100)
  local cut = osc.sanitize(euro, 120)
  -- 120 bytes would end inside the 40th euro sign (1 + 39 * 3 = 118 whole bytes): the cut steps back.
  eq(#cut, 118, "osc.sanitize: stepped back to the character boundary")
  eq(cut:byte(-1), 172, "osc.sanitize: ends on the last byte of a whole character")
  eq(vim.fn.strchars(cut), 40, "osc.sanitize: no character is split")

  local seq = osc.user_var("MUX_NVIM", "1")
  eq(
    seq,
    "\27]1337;SetUserVar=MUX_NVIM=" .. vim.base64.encode("1") .. "\7",
    "osc.user_var: exact sequence"
  )
  local bad, err = osc.user_var("a=b;c", "x")
  eq(bad, nil, "osc.user_var: a name that could end the sequence is refused")
  ok(err and err:find("name", 1, true), "osc.user_var: ... with a reason")
  eq((select(1, osc.user_var("X", 5))), nil, "osc.user_var: the value must be a string")
  ok(
    not osc.user_var("X", "a\27]0;pwn\7"):find("pwn", 1, true),
    "osc.user_var: the value is base64, never raw"
  )

  eq(
    osc.wrap_tmux("\27]1;x\7"),
    "\27Ptmux;\27\27]1;x\7\27\\",
    "osc.wrap_tmux: ESC doubled inside the envelope"
  )
  local saved_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux-1/default,1,0"
  eq(osc.wrap("S"), "\27Ptmux;S\27\\", "osc.wrap: without the flag, $TMUX decides (in tmux)")
  vim.env.TMUX = ""
  eq(osc.wrap("S"), "S", "osc.wrap: without the flag, an empty $TMUX is not tmux")
  vim.env.TMUX = saved_tmux
  eq(osc.wrap("S", false), "S", "osc.wrap: not in tmux, unchanged")
  eq(osc.wrap("S", true), "\27Ptmux;S\27\\", "osc.wrap: in tmux, wrapped")

  local saved = vim.api.nvim_ui_send
  local sent = {}
  vim.api.nvim_ui_send = function(s)
    sent[#sent + 1] = s
  end
  eq((osc.send("abc")), true, "osc.send: written")
  eq(#sent, 1, "osc.send: one call")
  eq(sent[1], "abc", "osc.send: payload as is")
  vim.api.nvim_ui_send = function()
    error("boom")
  end
  local sent_ok, sent_err = osc.send("x")
  eq(sent_ok, false, "osc.send: a failing write is reported, not raised")
  ok(sent_err and sent_err:find("boom", 1, true), "osc.send: ... with the reason")
  vim.api.nvim_ui_send = nil
  eq(osc.available(), false, "osc.available: false without nvim_ui_send")
  eq((osc.send("x")), false, "osc.send: false without nvim_ui_send")
  vim.api.nvim_ui_send = saved
end
