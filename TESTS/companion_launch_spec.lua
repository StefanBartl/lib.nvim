-- TESTS/companion_launch_spec.lua — lib.nvim.companion.launch: the inner nvim argv, the terminal
-- defaults per platform (from an env table, no process), template expansion ({cmd}, {title},
-- {shell}, {applescript}) and the refusals. Nothing here spawns.

return function(H)
  local eq, ok = H.eq, H.ok
  local launch = require("lib.nvim.companion.launch")

  -- literals and the rtp value
  eq(launch.lua_literal([[\\.\pipe\nvim.1.0]]), [=[[[\\.\pipe\nvim.1.0]]]=], "literal: long string")
  eq(launch.lua_literal("a]]b"), nil, "literal: a ]] cannot be held")
  eq(
    launch.rtp_value([[C:\Program Files\lib.nvim\]]),
    "C:/Program\\ Files/lib.nvim",
    "rtp: slashes, space, trailing slash"
  )
  eq(launch.rtp_value("/a,b/c"), "/a\\,b/c", "rtp: comma")

  -- the inner command
  local inner = {
    progpath = "/usr/bin/nvim",
    root = "/home/u/lib.nvim",
    server = "/tmp/nvim.sock",
    id = 7,
  }
  local argv = launch.inner_argv(inner)
  eq(argv[1], "/usr/bin/nvim", "inner: progpath first")
  eq(table.concat(argv, " ", 2, 6), "-u NONE -i NONE -n", "inner: no config, no shada, no swap")
  eq(argv[7], "--cmd", "inner: rtp cmd")
  eq(argv[8], "set rtp^=/home/u/lib.nvim", "inner: rtp value")
  eq(argv[9], "--cmd", "inner: start cmd")
  eq(
    argv[10],
    "lua require('lib.nvim.companion.client').start({ server = [[/tmp/nvim.sock]], id = 7 })",
    "inner: the client start line"
  )
  eq(#argv, 10, "inner: nothing else")
  local hl = launch.inner_argv(vim.tbl_extend("force", inner, { headless = true }))
  eq(hl[7], "--headless", "inner: headless flag before the --cmds")
  eq(#hl, 11, "inner: headless adds one element")
  eq(
    select(2, launch.inner_argv(vim.tbl_extend("force", inner, { server = "x]]y" }))) ~= nil,
    true,
    "inner: unliteral server refused"
  )
  eq(
    select(2, launch.inner_argv(vim.tbl_extend("force", inner, { id = 1.5 }))),
    "id must be an integer",
    "inner: id"
  )

  -- platform defaults
  local function env(os_name, present, terminal)
    local set = {}
    for _, n in ipairs(present) do
      set[n] = true
    end
    return {
      os = os_name,
      executable = function(n)
        return set[n] == true
      end,
      TERMINAL = terminal,
    }
  end
  local t = launch.default_terminal(env("windows", { "wt.exe", "cmd.exe" }))
  eq(t[1], "wt.exe", "windows: Windows Terminal first")
  eq(
    table.concat(t, " "),
    "wt.exe -w new new-tab --title {title} {cmd}",
    "windows: a new window with the title"
  )
  t = launch.default_terminal(env("windows", { "cmd.exe" }))
  eq(table.concat(t, " ", 1, 3), "cmd.exe /c start", "windows: cmd.exe start as the fallback")
  -- `start` takes its first QUOTED argument as the window title; libuv quotes an argument only
  -- when it holds whitespace or is empty, so a one-word title would reach `start` bare and be
  -- taken as the program. The title element is therefore empty (libuv passes it as `""`).
  eq(t[4], "", "windows: an empty title element for start, never a bare word")
  eq(t[5], "{cmd}", "windows: the command after it")
  eq(#t, 5, "windows: nothing else")
  ok(not table.concat(t, " "):find("{title}", 1, true), "windows: no {title} in the fallback")
  local none, err = launch.default_terminal(env("windows", {}))
  eq(none, nil, "windows: nothing found")
  ok(err:find("wt.exe", 1, true), "windows: the error names the candidates")
  t = launch.default_terminal(env("windows", { "wt.exe" }, "alacritty"))
  eq(t[1], "wt.exe", "windows: $TERMINAL is not consulted")

  t = launch.default_terminal(env("macos", { "osascript" }))
  eq(t[1], "osascript", "macos: Terminal.app through osascript")
  ok(t[3]:find("{applescript}", 1, true), "macos: the command goes in as an AppleScript literal")
  t = launch.default_terminal(env("macos", { "osascript", "kitty" }, "kitty"))
  eq(table.concat(t, " "), "kitty -e {cmd}", "macos: $TERMINAL wins when it is installed")
  t = launch.default_terminal(env("macos", { "osascript" }, "kitty"))
  eq(t[1], "osascript", "macos: a $TERMINAL that is not installed is skipped")
  eq(launch.default_terminal(env("macos", {})), nil, "macos: nothing found")

  t = launch.default_terminal(env("linux", { "gnome-terminal", "konsole", "xterm" }))
  eq(
    table.concat(t, " "),
    "gnome-terminal --title {title} -- {cmd}",
    "linux: gnome-terminal before konsole"
  )
  t = launch.default_terminal(env("linux", { "x-terminal-emulator", "gnome-terminal" }))
  eq(t[1], "x-terminal-emulator", "linux: the alternatives link first")
  t = launch.default_terminal(env("linux", { "konsole", "xterm" }))
  eq(table.concat(t, " "), "konsole -e {cmd}", "linux: konsole")
  t = launch.default_terminal(env("linux", { "xterm" }))
  eq(table.concat(t, " "), "xterm -T {title} -e {cmd}", "linux: xterm last")
  t = launch.default_terminal(env("linux", { "foot", "xterm" }, "foot"))
  eq(table.concat(t, " "), "foot -e {cmd}", "linux: $TERMINAL first")
  -- $TERMINAL names a terminal whose -e takes ONE string: never `-e {cmd}` (gnome-terminal
  -- would fail on the inner `-u`)
  t = launch.default_terminal(env("linux", { "gnome-terminal", "xterm" }, "gnome-terminal"))
  eq(
    table.concat(t, " "),
    "gnome-terminal --title {title} -- {cmd}",
    "linux: $TERMINAL=gnome-terminal uses --"
  )
  local gt = "/usr/bin/gnome-terminal"
  t = launch.default_terminal(env("linux", { gt }, gt))
  eq(t[1], gt, "linux: $TERMINAL as a path is kept")
  eq(t[4], "--", "linux: and recognized by its basename")
  t = launch.default_terminal(env("linux", { "xfce4-terminal" }, "xfce4-terminal"))
  eq(table.concat(t, " "), "xfce4-terminal -e {shell}", "linux: xfce4-terminal -e takes a line")
  eq(launch.terminal_template("tilix")[3], "{shell}", "template: tilix")
  eq(launch.terminal_template("mate-terminal")[3], "{shell}", "template: mate-terminal")
  eq(launch.terminal_template("terminator")[3], "{shell}", "template: terminator")
  eq(table.concat(launch.terminal_template("kitty"), " "), "kitty -e {cmd}", "template: kitty")
  t = launch.default_terminal(env("macos", { "osascript", "gnome-terminal" }, "gnome-terminal"))
  eq(t[4], "--", "macos: the same mapping for $TERMINAL")
  t = launch.default_terminal(env("linux", { "xterm" }, ""))
  eq(t[1], "xterm", "linux: an empty $TERMINAL is unset")
  eq(launch.default_terminal(env("linux", {})), nil, "linux: nothing found")

  -- expansion
  local cmd = { "nvim", "--cmd", "set rtp^=/x", "--cmd", "lua start('a')" }
  local out = launch.expand({ "wt.exe", "-w", "new", "--title", "{title}", "{cmd}" }, cmd, "Memory")
  eq(
    table.concat(out, "|"),
    "wt.exe|-w|new|--title|Memory|nvim|--cmd|set rtp^=/x|--cmd|lua start('a')",
    "expand: {cmd} spliced, {title} replaced"
  )
  out = launch.expand({ "cmd.exe", "/c", "start", "", "{cmd}" }, cmd, "Memory")
  eq(out[4], "", "expand: an empty element is kept")
  eq(out[5], "nvim", "expand: the command follows it")
  out = launch.expand({ "sh", "-c", "exec {shell}" }, cmd, "T")
  eq(
    out[3],
    "exec nvim --cmd 'set rtp^=/x' --cmd 'lua start('\\''a'\\'')'",
    "expand: {shell} is one POSIX-quoted line"
  )
  out = launch.expand({ "osascript", "-e", "do script {applescript}" }, { "nvim", "a b" }, "T")
  eq(out[3], "do script \"nvim 'a b'\"", "expand: {applescript} is a double-quoted literal")
  eq(
    launch.applescript_literal('say "hi" \\ there'),
    '"say \\"hi\\" \\\\ there"',
    "applescript: quotes and backslashes"
  )
  eq(
    select(2, launch.expand({ "xterm" }, cmd, "T")),
    "terminal has no {cmd}, {shell} or {applescript}",
    "expand: no placeholder"
  )
  eq(select(2, launch.expand({}, cmd, "T")), "terminal must be a non-empty list", "expand: empty")
  eq(
    select(2, launch.expand({ "x", 1 }, cmd, "T")),
    "terminal holds a non-string",
    "expand: non-string"
  )
  local _, qerr = launch.expand({ "sh", "-c", "{shell}" }, { "nvim", "a\nb" }, "T")
  ok(
    qerr and qerr:find("cannot quote", 1, true),
    "expand: a control character cannot go through a shell"
  )

  -- the whole argv, default terminal or a template
  local full = launch.argv(inner, nil, env("linux", { "xterm" }), "Mem")
  eq(full[1], "xterm", "argv: default terminal of the env")
  eq(full[3], "Mem", "argv: title")
  eq(full[5], "/usr/bin/nvim", "argv: inner after -e")
  full = launch.argv(inner, { "{cmd}" }, env("linux", {}), "Mem")
  eq(full[1], "/usr/bin/nvim", "argv: a bare template needs no terminal")
  eq(
    select(2, launch.argv(inner, nil, env("linux", {}), "Mem")) ~= nil,
    true,
    "argv: no terminal is an error"
  )
end
