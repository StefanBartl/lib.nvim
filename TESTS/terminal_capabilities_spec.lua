-- TESTS/terminal_capabilities_spec.lua — lib.nvim.terminal.capabilities: env heuristic, session cache,
-- one warning per missing capability.

return function(H)
  local eq, ok = H.eq, H.ok
  local caps = require("lib.nvim.terminal.capabilities")

  -- detect is pure and reads the table it is given
  local kitty = caps.detect({ TERM = "xterm-kitty" })
  eq(kitty.kitty_graphics, true, "kitty: kitty graphics")
  eq(kitty.osc1337_images, false, "kitty: not OSC 1337")
  eq(kitty.host.name, "Kitty", "kitty: the host is named")

  local wez = caps.detect({ WEZTERM_PANE = "1", COLORTERM = "truecolor" })
  eq(wez.kitty_graphics, true, "wezterm: kitty graphics")
  eq(wez.osc1337_images, true, "wezterm: OSC 1337")
  eq(wez.sixel, true, "wezterm: sixel")
  eq(wez.truecolor, true, "wezterm: truecolor from COLORTERM")

  local iterm = caps.detect({ TERM_PROGRAM = "iTerm.app" })
  eq(iterm.osc1337_images, true, "iterm2: OSC 1337")
  eq(iterm.kitty_graphics, false, "iterm2: no kitty graphics")

  local ghostty = caps.detect({ TERM_PROGRAM = "ghostty" })
  eq(ghostty.kitty_graphics, true, "ghostty: kitty graphics")
  eq(
    caps.detect({ GHOSTTY_RESOURCES_DIR = "/x" }).kitty_graphics,
    true,
    "ghostty by its resource dir"
  )

  eq(caps.detect({ TERM = "foot" }).sixel, true, "foot: sixel")
  eq(caps.detect({ TERM = "xterm-256color-sixel" }).sixel, true, "a TERM naming sixel")
  eq(caps.detect({ TERM = "xterm-256color" }).sixel, false, "plain xterm: not known to")

  local plain = caps.detect({ TERM = "xterm-256color" })
  eq(plain.kitty_graphics, false, "plain: no kitty graphics")
  eq(plain.osc1337_images, false, "plain: no OSC 1337")
  eq(plain.truecolor, false, "plain: no truecolor")
  eq(caps.detect({ COLORTERM = "24bit" }).truecolor, true, "COLORTERM=24bit")
  eq(caps.detect({ COLORTERM = "TrueColor" }).truecolor, true, "COLORTERM is case-insensitive")
  eq(
    caps.detect({ KITTY_WINDOW_ID = "" }).kitty_graphics,
    false,
    "an empty variable counts as unset"
  )

  -- tmux is reported through the host
  local tm = caps.detect({ TMUX = "/tmp/tmux", TERM = "xterm-kitty" })
  eq(tm.host.in_tmux, true, "tmux: reported")
  ok(tm.host.hint ~= nil, "tmux: with the passthrough hint")

  -- names
  local names = caps.names()
  eq(#names, 4, "names: the capability list")
  names[#names + 1] = "junk"
  eq(#caps.names(), 4, "names: a copy")

  -- supports: session cache, reset re-reads the environment
  local real_env_term = vim.env.TERM
  local real_colorterm = vim.env.COLORTERM
  vim.env.TERM = "xterm-256color"
  vim.env.COLORTERM = nil
  caps.reset()
  eq(caps.supports("truecolor"), false, "supports: from vim.env")
  vim.env.COLORTERM = "truecolor"
  eq(caps.supports("truecolor"), false, "supports: cached for the session")
  caps.reset()
  eq(caps.supports("truecolor"), true, "supports: reset re-detects")
  eq(pcall(caps.supports, "teleport"), false, "supports: an unknown capability is an error")

  -- require: ONE warning per missing capability, then silence
  caps.reset()
  vim.env.TERM = "xterm-256color"
  vim.env.COLORTERM = nil
  local seen = {}
  local function sink(msg)
    seen[#seen + 1] = msg
  end
  eq(
    caps.require("kitty_graphics", { feature = "inline images", notify = sink }),
    false,
    "require: missing"
  )
  eq(#seen, 1, "require: warned once")
  ok(seen[1]:find("inline images", 1, true) ~= nil, "require: names the feature")
  ok(seen[1]:find("kitty_graphics", 1, true) ~= nil, "require: ... and the capability")
  eq(
    caps.require("kitty_graphics", { feature = "inline images", notify = sink }),
    false,
    "require: still missing"
  )
  eq(#seen, 1, "require: not warned again")
  eq(caps.require("sixel", { notify = sink }), false, "require: another capability")
  eq(#seen, 2, "require: ... has its own warning")
  vim.env.COLORTERM = "truecolor"
  caps.reset()
  eq(caps.require("truecolor", { notify = sink }), true, "require: present is true")
  eq(#seen, 2, "require: no warning when present")

  -- a second feature missing the same capability warns once for itself; the first stays silent
  caps.require("kitty_graphics", { feature = "inline images", notify = sink })
  local before = #seen
  eq(
    caps.require("kitty_graphics", { feature = "another plugin", notify = sink }),
    false,
    "require: other feature, still missing"
  )
  eq(#seen, before + 1, "require: a different feature gets its own warning")
  caps.require("kitty_graphics", { feature = "another plugin", notify = sink })
  caps.require("kitty_graphics", { feature = "inline images", notify = sink })
  eq(#seen, before + 1, "require: ... and neither repeats")

  -- reset forgets the warnings too
  vim.env.COLORTERM = nil
  caps.reset()
  local pre_reset = #seen
  caps.require("truecolor", { notify = sink })
  eq(#seen, pre_reset + 1, "require: after reset the warning can show again")

  -- the default sink is lib.nvim.notify at WARN
  caps.reset()
  local got
  H.with_patched(vim, "notify", function(msg, level)
    got = { msg = msg, level = level }
  end, function()
    caps.require("truecolor")
  end)
  ok(
    got ~= nil and got.level == vim.log.levels.WARN,
    "require: default sink warns through vim.notify"
  )

  vim.env.TERM = real_env_term
  vim.env.COLORTERM = real_colorterm
  caps.reset()
end
