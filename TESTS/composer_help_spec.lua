-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- TESTS/composer_help_spec.lua — lib.nvim.bindings.usercmd.composer.help
--
-- The opt-in option float: the entries engine (pure), the command-line
-- parsing and insertion, the float's item building, the dispatch hook, the
-- opt-in switch and the cheatsheet key. No window is opened here.

return function(H)
  local eq, ok = H.eq, H.ok

  local composer = require("lib.nvim.bindings.usercmd.composer")
  local tree = require("lib.nvim.bindings.usercmd.composer.tree")
  local parse = require("lib.nvim.bindings.usercmd.composer.parse")
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")
  local help_ui = require("lib.nvim.bindings.usercmd.composer.help.ui")
  local help = require("lib.nvim.bindings.usercmd.composer.help")

  local noop = function() end

  ---@type Lib.UserCmd.Composer.Spec
  local spec = {
    desc = "Help demo",
    routes = {
      { path = { "open" }, desc = "Open the thing", run = noop },
      { path = { "close" }, run = noop },
      { path = { "ui", "show" }, desc = "Show the UI", run = noop },
      { path = { "ui", "hide" }, desc = "Hide the UI", run = noop },
      {
        path = { "surround" },
        desc = "Wrap a target",
        args = {
          {
            name = "kind",
            enum = { "quote", "paren" },
            enum_desc = { quote = "double quotes", paren = "parentheses" },
          },
          { name = "target", desc = "what to wrap" },
        },
        flags = {
          { name = "dry", short = "d", bool = true, desc = "only report" },
          { name = "mode", enum = { "a", "b" }, enum_desc = { a = "first" }, desc = "how" },
        },
        kv = { { key = "view", enum = { "split", "vsplit" }, desc = "where" } },
        run = noop,
      },
    },
  }
  local root = tree.build(spec.routes)

  ---@param list Lib.UserCmd.Composer.Help.Entry[]
  ---@param kind string
  ---@return string[]
  local function labels(list, kind)
    local out = {}
    for _, e in ipairs(list) do
      if e.kind == kind then
        out[#out + 1] = e.label
      end
    end
    return out
  end

  -- ------------------------------------------------------------ entries
  local top = entries.compute(root, {}, "")
  eq(
    table.concat(labels(top.items, "heading"), ","),
    "Subcommands",
    "root: only the subcommand section"
  )
  eq(
    table.concat(labels(top.items, "sub"), ","),
    "close,open,surround",
    "root: leaf subcommands, sorted"
  )
  eq(table.concat(labels(top.items, "group"), ","), "ui", "root: a group is marked as one")
  for _, e in ipairs(top.items) do
    if e.label == "open" then
      eq(e.desc, "Open the thing", "sub: description from route.desc")
      eq(e.insert, "open", "sub: insert is the token")
    elseif e.label == "ui" then
      eq(e.desc, "hide, show", "group: summary of its children")
    end
  end

  local ui_level = entries.compute(root, { "ui" }, "")
  eq(table.concat(labels(ui_level.items, "sub"), ","), "hide,show", "group: its children")

  local arg_level = entries.compute(root, { "surround" }, "")
  eq(
    table.concat(labels(arg_level.items, "heading"), ","),
    "Argument,Flags,Key=value",
    "route: argument, flags and key=value sections"
  )
  eq(table.concat(labels(arg_level.items, "value"), ","), "quote,paren", "arg: enum values")
  for _, e in ipairs(arg_level.items) do
    if e.label == "quote" then
      eq(e.desc, "double quotes", "arg: enum_desc shown next to the value")
    end
  end
  eq(
    table.concat(labels(arg_level.items, "flag"), ","),
    "--dry|-d,--mode=<a|b>",
    "flags: long, short and value hint"
  )
  eq(
    table.concat(labels(arg_level.items, "kv"), ","),
    "view=<split|vsplit>",
    "kv: key with value hint"
  )

  -- A filled enum moves on to the next positional (a free-text hint row).
  local second = entries.compute(root, { "surround", "quote" }, "")
  eq(table.concat(labels(second.items, "hint"), ","), "{target}", "second positional: hint row")
  for _, e in ipairs(second.items) do
    if e.kind == "hint" then
      eq(e.insert, nil, "hint row is not pickable")
      eq(e.desc, "what to wrap", "hint row: arg desc")
    end
  end

  -- A flag already given is not offered again; kv likewise.
  local used = entries.compute(root, { "surround", "quote", "--dry", "view=split" }, "")
  eq(table.concat(labels(used.items, "flag"), ","), "--mode=<a|b>", "used flag is dropped")
  eq(#labels(used.items, "kv"), 0, "used kv key is dropped")

  -- A typed lead narrows by prefix; no match shows everything.
  local narrowed = entries.compute(root, {}, "o")
  eq(table.concat(labels(narrowed.items, "sub"), ","), "open", "lead narrows")
  eq(narrowed.filtered, true, "narrowed is reported")
  local nomatch = entries.compute(root, {}, "zzz")
  eq(#labels(nomatch.items, "sub"), 3, "no match: whole list instead of an empty float")
  eq(nomatch.filtered, false, "no match is not 'filtered'")

  -- Typing the value of a flag / kv key lists its enum.
  local flag_value = entries.compute(root, { "surround", "quote" }, "--mode=")
  eq(table.concat(labels(flag_value.items, "value"), ","), "a,b", "--flag= lists its enum")
  eq(flag_value.items[2].insert, "--mode=a", "flag value insert carries the prefix")
  local kv_value = entries.compute(root, { "surround", "quote" }, "view=v")
  eq(table.concat(labels(kv_value.items, "value"), ","), "vsplit", "key= lists its enum, narrowed")

  -- `--mode <lead>`: the value is the next token.
  local spaced = entries.compute(root, { "surround", "quote", "--mode" }, "")
  eq(table.concat(labels(spaced.items, "value"), ","), "a,b", "--flag <lead> lists its enum")

  -- Past a bare `--` everything is positional: no flag / kv rows.
  local dashed = entries.compute(root, { "surround", "--" }, "")
  eq(#labels(dashed.items, "flag"), 0, "after -- no flags")
  eq(#labels(dashed.items, "kv"), 0, "after -- no key=value")

  -- A route hidden by `available` is not offered (same filter as <Tab>).
  local gated = tree.build({
    { path = { "yes" }, run = noop },
    {
      path = { "no" },
      available = function()
        return false
      end,
      run = noop,
    },
  })
  eq(
    table.concat(labels(entries.compute(gated, {}, "").items, "sub"), ","),
    "yes",
    "available gates"
  )

  -- ------------------------------------------------------------ parse_line
  local s = help.parse_line("Clipboard")
  eq(s.name, "Clipboard", "parse: bare verb")
  eq(s.base, "Clipboard ", "parse: base gets the separating space")
  eq(#s.committed, 0, "parse: nothing committed")
  eq(s.lead, "", "parse: no lead")

  s = help.parse_line("Clipboard rep")
  eq(s.lead, "rep", "parse: unfinished token is the lead")
  eq(s.base, "Clipboard ", "parse: base stops before the lead")

  s = help.parse_line("Clipboard report  ")
  eq(s.lead, "", "parse: trailing space ends the token")
  eq(table.concat(s.committed, ","), "report", "parse: finished tokens")
  eq(s.base, "Clipboard report  ", "parse: base keeps the line as typed")

  s = help.parse_line("'<,'>Verb! sub arg")
  eq(s.name, "Verb", "parse: range prefix and bang are skipped")
  eq(s.base, "'<,'>Verb! sub ", "parse: base keeps range and bang")
  eq(s.lead, "arg", "parse: lead after a range")

  eq(help.parse_line("set number"), nil, "parse: lower-case builtin is not a verb")
  eq(help.parse_line("Verb=1"), nil, "parse: name glued to a symbol is not a verb")
  eq(help.parse_line(""), nil, "parse: empty line")

  -- ------------------------------------------------------------ insertion
  s = help.parse_line("Verb su")
  eq(
    help.insertion(s, { insert = "surround" }),
    "Verb surround ",
    "insert: replaces the lead, adds a space"
  )
  eq(
    help.insertion(s, { insert = "--mode=", partial = true }),
    "Verb --mode=",
    "insert: a partial pick continues without a space"
  )
  eq(
    help.insertion(s, { insert = "a\nb" }),
    "Verb ab ",
    "insert: control characters never reach the line"
  )

  -- ------------------------------------------------------------ ui items
  local items, first = help_ui.build_items(arg_level.items)
  ok(first ~= nil, "ui: a pickable item exists")
  eq(items[1].selectable, false, "ui: heading row is inert")
  eq(items[1].entry.kind, "heading", "ui: items keep their entry")
  local single = help_ui.build_items(top.items)
  eq(single[1].entry.kind ~= "heading", true, "ui: a lone section drops its heading")
  local hint_items = help_ui.build_items(second.items)
  local hint_row
  for _, it in ipairs(hint_items) do
    if it.entry.kind == "hint" then
      hint_row = it
    end
  end
  eq(hint_row.selectable, false, "ui: hint row is inert")
  ok(hint_row.lines[1]:find("what to wrap", 1, true) ~= nil, "ui: description is drawn")
  local long = help_ui.build_items({
    { kind = "sub", label = "a", insert = "a", desc = string.rep("long ", 100) },
  })
  ok(
    vim.fn.strdisplaywidth(long[1].lines[1]) <= vim.o.columns,
    "ui: a long description is cut to the screen"
  )
  local _, none = help_ui.build_items({ { kind = "hint", label = "{x}" } })
  eq(none, nil, "ui: nothing pickable -> no first item")

  -- ------------------------------------------------------------ opt-in
  local saved = vim.deepcopy(help.cfg)
  help.cfg.enable = false
  eq(help.enabled({}), false, "opt-in: off by default")
  eq(help.enabled({ help = true }), true, "opt-in: spec.help = true turns a verb on")
  help.cfg.enable = true
  eq(help.enabled({}), true, "opt-in: enable turns every verb on")
  eq(help.enabled({ help = false }), false, "opt-in: spec.help = false wins over enable")
  help.cfg.enable = false

  -- ------------------------------------------------------------ dispatch hook
  local texts = {}
  local plain = {
    info = function(m)
      texts[#texts + 1] = "info:" .. m
    end,
    error = function(m)
      texts[#texts + 1] = "error:" .. m
    end,
  }
  local function dispatch(verb_spec, notifier, fargs)
    return parse.dispatch(
      "HelpDemo",
      verb_spec,
      tree.build(verb_spec.routes),
      { fargs = fargs },
      notifier
    )
  end

  dispatch(spec, plain, {})
  ok(
    texts[1]:find("^info:Usage: :HelpDemo"),
    "dispatch: a notifier without help keeps the usage text"
  )
  texts = {}
  dispatch(spec, plain, { "nope" })
  ok(
    texts[1]:find("^error:unknown subcommand 'nope'"),
    "dispatch: unknown subcommand text unchanged"
  )
  texts = {}
  dispatch(spec, plain, { "ui" })
  ok(texts[1]:find("needs a subcommand", 1, true) ~= nil, "dispatch: group text unchanged")

  local calls = {}
  local with_help = vim.tbl_extend("force", plain, {
    help = function(tokens, reason, fallback)
      calls[#calls + 1] = { table.concat(tokens, " "), reason }
      eq(type(fallback), "function", "dispatch: fallback is handed over")
      return true
    end,
  })
  texts = {}
  dispatch(spec, with_help, {})
  dispatch(spec, with_help, { "ui" })
  dispatch(spec, with_help, { "ui", "nope" })
  eq(#texts, 0, "dispatch: a taking-over help suppresses the notification")
  eq(calls[1][1], "", "dispatch: bare verb shows the root level")
  eq(calls[2][1], "ui", "dispatch: group shows its level")
  eq(calls[3][1], "ui", "dispatch: unknown token shows the matched level")
  eq(calls[3][2], "unknown subcommand 'nope'", "dispatch: unknown token becomes the title")

  -- A missing required argument opens the float at that level, too; a wrong value does not.
  calls = {}
  texts = {}
  dispatch(spec, with_help, { "surround" })
  eq(calls[1][1], "surround", "dispatch: missing argument shows the route's level")
  ok(calls[1][2]:find("^missing required argument"), "dispatch: the missing argument is the title")
  calls = {}
  dispatch(spec, with_help, { "surround", "bogus" })
  eq(#calls, 0, "dispatch: an invalid value is not a help case")
  ok(texts[1]:find("^error:argument"), "dispatch: an invalid value keeps its message")

  local declining = vim.tbl_extend("force", plain, {
    help = function()
      return false
    end,
  })
  texts = {}
  dispatch(spec, declining, {})
  ok(texts[1]:find("^info:Usage"), "dispatch: a declining help falls back to the usage text")

  -- spec.default still wins over the help for a bare verb.
  local default_ran = false
  dispatch({
    routes = spec.routes,
    default = function()
      default_ran = true
    end,
  }, with_help, {})
  eq(default_ran, true, "dispatch: spec.default keeps precedence")

  -- Range and bang survive into the float's base line.
  local seen_base
  local real_open2 = help.open
  help.open = function(_, st)
    seen_base = st.base
    return true
  end
  local ui_real = vim.api.nvim_list_uis
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  local flush = vim.schedule
  vim.schedule = function(fn)
    fn()
  end
  help.on_dispatch(
    "HelpDemo",
    { help = true },
    root,
    { "ui" },
    nil,
    nil,
    { range = 2, line1 = 3, line2 = 5, bang = true }
  )
  vim.schedule = flush
  vim.api.nvim_list_uis = ui_real
  help.open = real_open2
  eq(seen_base, "3,5HelpDemo! ui ", "on_dispatch: range and bang are kept")

  -- on_dispatch: off for a verb that did not opt in, and without a UI.
  eq(help.on_dispatch("HelpDemo", spec, root, {}), false, "on_dispatch: not opted in")
  eq(
    help.on_dispatch("HelpDemo", { help = true, routes = spec.routes }, root, {}),
    #vim.api.nvim_list_uis() > 0,
    "on_dispatch: needs a UI"
  )

  -- ------------------------------------------------------------ registered verb
  composer.verb("ComposerHelpSpecVerb", { help = true, routes = spec.routes })
  composer.verb("ComposerHelpSpecOff", { routes = spec.routes })
  local opened
  local real_open = help.open
  help.open = function(r, state, opts)
    opened = { root = r, state = state, opts = opts }
    return true
  end
  eq(help.from_cmdline("ComposerHelpSpecVerb ui s"), true, "from_cmdline: opted-in verb opens")
  eq(opened.state.lead, "s", "from_cmdline: the lead reaches the float")
  eq(
    table.concat(opened.state.committed, ","),
    "ui",
    "from_cmdline: finished tokens reach the float"
  )
  eq(opened.opts.restore, "ComposerHelpSpecVerb ui s", "from_cmdline: Esc restores the typed line")
  opened = nil
  eq(help.from_cmdline("ComposerHelpSpecOff "), false, "from_cmdline: verb that did not opt in")
  eq(help.from_cmdline("NoSuchVerbAnywhere "), false, "from_cmdline: unknown verb")
  eq(help.from_cmdline("set nu"), false, "from_cmdline: not a verb")
  eq(opened, nil, "from_cmdline: nothing opened in the refused cases")
  help.open = real_open

  -- ------------------------------------------------------------ keymap
  local lhs = "<F19>"
  composer.setup({ help = { keymap = lhs } })
  local map = vim.fn.maparg(lhs, "c", false, true)
  eq(map.expr, 1, "keymap: an expr mapping in command-line mode")
  composer.setup({ help = { keymap = false } })
  eq(vim.fn.maparg(lhs, "c", false, true).lhs, nil, "keymap: false removes it")
  eq(composer.help == nil, false, "composer.help is reachable lazily")

  help.cfg.enable, help.cfg.keymap = saved.enable, saved.keymap
end
