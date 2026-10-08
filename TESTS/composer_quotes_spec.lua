-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- TESTS/composer_quotes_spec.lua -- lib.nvim.bindings.usercmd.composer, `spec.quotes`
--
-- A verb that cuts `ctx.raw.args` with a quote-aware tokenizer (replacer.nvim's
-- `:Replace "foo bar" baz`) sets `quotes = true`; `<Tab>` completion and the
-- help float then count a quoted run as ONE token, so the slot they offer is the
-- slot the handler fills. Without the flag nothing changes. Real regression:
-- `:Replace "foo bar" <M-h>` offered `[{scope}]` instead of `{new}`, and
-- `:Replace "foo bar" baz <M-h>` offered no argument at all.

return function(H)
  local eq, ok = H.eq, H.ok

  local composer = require("lib.nvim.bindings.usercmd.composer")
  local tree = require("lib.nvim.bindings.usercmd.composer.tree")
  local tokens = require("lib.nvim.bindings.usercmd.composer.tokens")
  local complete = require("lib.nvim.bindings.usercmd.composer.complete")
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")
  local help = require("lib.nvim.bindings.usercmd.composer.help")

  local noop = function() end

  -- ------------------------------------------------------------ the tokenizer
  ---@param text string
  ---@return { values: string, raws: string, open: boolean, unclosed: boolean }
  local function split(text)
    local parts, open, unclosed = tokens.split_quoted(text)
    local values, raws = {}, {}
    for i, part in ipairs(parts) do
      values[i], raws[i] = part.value, part.raw
    end
    return {
      values = table.concat(values, "|"),
      raws = table.concat(raws, "|"),
      open = open,
      unclosed = unclosed,
    }
  end

  local got = split([["foo bar" baz]])
  eq(got.values, "foo bar|baz", "split: a double-quoted run is one token")
  eq(got.raws, [["foo bar"|baz]], "split: ... and keeps its spelling as typed")
  eq(got.open, true, "split: the token touching the end is still being typed")
  eq(got.unclosed, false, "split: ... and no quote is open")

  got = split([["foo bar" baz ]])
  eq(got.values, "foo bar|baz", "split: a trailing blank changes nothing about the tokens")
  eq(got.open, false, "split: ... but ends the last token")

  eq(split([['a b' c]]).values, "a b|c", "split: single quotes group too")
  eq(split([["it's here" x]]).values, "it's here|x", "split: the other quote is plain text inside")
  eq(
    split([["say \"hi\" now" x]]).values,
    [[say "hi" now|x]],
    "split: an escaped quote stays inside"
  )
  eq(split([[foo\ bar baz]]).values, "foo bar|baz", "split: an escaped blank outside quotes")
  eq(
    split([[C:\Users\x "C:\my dir\a"]]).values,
    [[C:\Users\x|C:\my dir\a]],
    "split: other backslashes stay, a Windows path is read as typed"
  )
  eq(split([[a\\b]]).values, [[a\b]], "split: an escaped backslash")
  eq(split([["foo"bar]]).values, "foo|bar", "split: a token ends at its closing quote")
  eq(split([[a"b c"]]).values, [[a"b|c"]], "split: a quote in the middle of a token is a character")
  eq(split([[foo\]]).values, [[foo\]], "split: a lone trailing backslash stays")

  got = split([["foo bar]])
  eq(got.values, "foo bar", "split: an unterminated quote runs to the end")
  eq(got.raws, [["foo bar]], "split: ... raw is the tail as typed")
  eq(got.open, true, "split: ... it is the token being typed")
  eq(got.unclosed, true, "split: ... inside a quote")

  got = split([["foo bar"]])
  eq(got.open, true, "split: a closing quote at the very end can still be continued")
  eq(got.unclosed, false, "split: ... yet nothing is open")

  got = split([["]])
  eq(got.values .. "|" .. got.raws, [[|"]], "split: a lone quote is an empty token")
  eq(got.open and got.unclosed, true, "split: ... being typed inside a quote")

  got = split("")
  eq(got.values, "", "split: nothing typed")
  eq(got.open or got.unclosed, false, "split: ... nothing open")
  eq(split("   ").open, false, "split: blanks only")

  -- ------------------------------------------------------------ a Replace-like verb
  local function spec_of(quotes)
    return {
      desc = "Quotes demo",
      help = true,
      quotes = quotes,
      routes = {
        {
          path = {},
          args = {
            { name = "old", type = "STRING", desc = "The pattern to search for" },
            { name = "new", type = "STRING", desc = "The replacement text" },
            {
              name = "scope",
              type = "STRING",
              optional = true,
              values = { "%", "cwd", ".", "root" },
              desc = "Where to search",
              enum_desc = { cwd = "Current working directory" },
            },
          },
          flags = { { name = "dry", bool = true, desc = "Only report" } },
          run = noop,
        },
      },
    }
  end
  local on_spec, off_spec = spec_of(true), spec_of(nil)
  composer.verb("ComposerQuotesSpecOn", on_spec)
  composer.verb("ComposerQuotesSpecOff", off_spec)
  local on_root = tree.build(on_spec.routes)

  --- The labels under the "Argument" heading for what the float would show
  --- for `line`.
  ---@param line string
  ---@param quotes? boolean
  ---@return string
  local function argument_rows(line, quotes)
    local st = help.parse_line(line, quotes)
    local items = entries.compute(on_root, st.committed, st.lead).items
    local out, inside = {}, false
    for _, e in ipairs(items) do
      if e.kind == "heading" then
        inside = e.label == "Argument"
      elseif inside then
        out[#out + 1] = e.label
      end
    end
    return table.concat(out, ",")
  end

  -- The float
  eq(argument_rows("ComposerQuotesSpecOn "), "{old}", "float: the first slot is {old}")
  eq(argument_rows("ComposerQuotesSpecOn foo "), "{new}", "float: an unquoted pattern fills it")
  eq(
    argument_rows([[ComposerQuotesSpecOn "foo bar" ]]),
    "{new}",
    "float: a quoted pattern with a blank fills ONE slot, so {new} is next"
  )
  eq(
    argument_rows([[ComposerQuotesSpecOn "foo bar" baz ]]),
    "[{scope}],%,cwd,.,root",
    "float: ... and the scope row is still on offer after the replacement"
  )
  eq(
    argument_rows([[ComposerQuotesSpecOn 'a b' 'c d' root ]]),
    "",
    "float: nothing is left to offer once every slot is filled"
  )
  eq(
    argument_rows([[ComposerQuotesSpecOn foo "ba]]),
    "{new}",
    "float: an unterminated quote is the token being typed, so the slot stays {new}"
  )

  -- Without the flag nothing changes: the blank split stays the rule.
  eq(
    argument_rows([[ComposerQuotesSpecOff "foo bar" ]]),
    "[{scope}],%,cwd,.,root",
    "default: a verb without `quotes` still cuts at every blank"
  )
  local off_state = help.parse_line([[ComposerQuotesSpecOff "foo bar" ]])
  eq(table.concat(off_state.committed, "|"), [["foo|bar"]], "default: the committed tokens")

  -- An explicit argument beats the registry.
  eq(
    table.concat(help.parse_line([[ComposerQuotesSpecOff "foo bar" ]], true).committed, "|"),
    "foo bar",
    "parse_line: `quotes = true` is honoured for a verb that did not ask"
  )
  eq(
    table.concat(help.parse_line([[ComposerQuotesSpecOn "foo bar" ]], false).committed, "|"),
    [["foo|bar"]],
    "parse_line: `quotes = false` is honoured for a verb that did"
  )
  eq(
    help.parse_line([[NoSuchVerbQuotesSpec "foo bar" ]]).committed[1],
    [["foo]],
    "parse_line: an unregistered verb is cut at blanks"
  )

  -- The token being typed keeps its quote, and the line is put back as typed.
  local st = help.parse_line([[ComposerQuotesSpecOn "foo ba]])
  eq(st.lead, [["foo ba]], "parse_line: the lead is the whole open quoted run, as typed")
  eq(#st.committed, 0, "parse_line: ... nothing before it is committed")
  eq(st.base, "ComposerQuotesSpecOn ", "parse_line: base stops before the opening quote")

  st = help.parse_line([[ComposerQuotesSpecOn "foo bar"]])
  eq(st.lead, [["foo bar"]], "parse_line: a closed quote at the end is still the lead")

  st = help.parse_line([[ComposerQuotesSpecOn "foo bar" baz ]])
  eq(
    table.concat(st.committed, "|"),
    "foo bar|baz",
    "parse_line: quoted and plain tokens are committed as values"
  )
  eq(
    st.base,
    [[ComposerQuotesSpecOn "foo bar" baz ]],
    "parse_line: base keeps the quoting as typed"
  )
  local scope_pick
  for _, e in ipairs(entries.compute(on_root, st.committed, st.lead).items) do
    if e.label == "cwd" then
      scope_pick = e
    end
  end
  eq(
    help.insertion(st, scope_pick),
    [[ComposerQuotesSpecOn "foo bar" baz cwd ]],
    "insertion: a pick lands behind the quoted pattern, which is not touched"
  )

  -- The cheatsheet path (what the key calls) reads the flag off the registry.
  local real_open, opened = help.open, nil
  help.open = function(_, state)
    opened = state
    return true
  end
  local from_ok, from_err = pcall(function()
    eq(help.from_cmdline([[ComposerQuotesSpecOn "foo bar" ]]), true, "from_cmdline: opens")
    eq(
      table.concat(opened.committed, "|"),
      "foo bar",
      "from_cmdline: the float gets the quoted pattern as one token"
    )
  end)
  help.open = real_open
  if not from_ok then
    error(from_err, 0)
  end

  -- ------------------------------------------------------------ <Tab>
  eq(
    table.concat(complete.committed([[V "foo bar" ba]], "ba", true), "|"),
    "foo bar",
    "committed: a quoted run is one token and the lead is dropped"
  )
  eq(
    table.concat(complete.committed([[V "foo bar" ba]], "ba"), "|"),
    [["foo|bar"]],
    "committed: without `quotes` it is cut at blanks, as before"
  )
  eq(
    table.concat(complete.committed([[V "foo bar" ]], "", true), "|"),
    "foo bar",
    "committed: a finished quoted token with nothing after it"
  )
  eq(
    #complete.committed([[V "foo ba]], "ba", true),
    0,
    "committed: inside an open quote the lead is that quoted run, not a finished token"
  )

  ---@param list string[]
  ---@return string
  local function join(list)
    return table.concat(list, ",")
  end
  eq(
    join(complete.candidates(on_root, "", [[V "foo bar" baz ]], true)),
    "%,cwd,.,root",
    "candidates: the third slot after a quoted pattern is the scope"
  )
  eq(
    join(complete.candidates(on_root, "", [[V "foo bar" baz ]])),
    "",
    "candidates: ... where the blank split sees a fourth slot and offers nothing"
  )
  eq(
    join(complete.candidates(on_root, "", [[V 'a b' 'c d' ]], true)),
    "%,cwd,.,root",
    "candidates: single quotes count the same"
  )
  eq(
    join(complete.candidates(on_root, "--d", [[V "foo --d]])),
    "--dry",
    "candidates: without `quotes` a flag-looking word inside a quote is completed"
  )
  eq(
    join(complete.candidates(on_root, "--d", [[V "foo --d]], true)),
    "",
    "candidates: ... with it, the words of an open quote are text"
  )

  -- The wiring on the real command: the registered completer asks the spec.
  local on_cc = vim.fn.getcompletion([[ComposerQuotesSpecOn "foo bar" baz ]], "cmdline")
  ok(vim.tbl_contains(on_cc, "cwd"), "e2e: the command completes the scope after a quoted pattern")
  local off_cc = vim.fn.getcompletion([[ComposerQuotesSpecOff "foo bar" baz ]], "cmdline")
  ok(not vim.tbl_contains(off_cc, "cwd"), "e2e: ... but not a verb that did not ask for quotes")
  on_spec.quotes = nil
  on_cc = vim.fn.getcompletion([[ComposerQuotesSpecOn "foo bar" baz ]], "cmdline")
  ok(not vim.tbl_contains(on_cc, "cwd"), "e2e: the flag is read on every call, not frozen")

  -- ------------------------------------------------------------ dispatch
  -- The flag and argument checks see the tokens the handler will see: a quoted
  -- run that holds a flag-looking word is text, and `"a"b` is two arguments.
  local captured, notes
  local function run_spec(quotes)
    return {
      desc = "Quotes dispatch demo",
      quotes = quotes,
      routes = {
        {
          path = {},
          args = {
            { name = "old", type = "STRING" },
            { name = "new", type = "STRING", optional = true },
          },
          flags = { { name = "dry", bool = true } },
          run = function(ctx)
            captured = ctx
          end,
        },
      },
    }
  end
  composer.verb("ComposerQuotesRunOn", run_spec(true))
  composer.verb("ComposerQuotesRunOff", run_spec(nil))
  local real_notify = vim.notify
  vim.notify = function(msg)
    notes = (notes or "") .. tostring(msg) .. "\n"
  end
  local dispatch_ok, dispatch_err = pcall(function()
    captured, notes = nil, nil
    vim.cmd([[ComposerQuotesRunOn "x --dry" y]])
    ok(captured ~= nil, "dispatch: a quoted flag-looking word does not reject the line")
    eq(captured and captured.args.old, "x --dry", "dispatch: ... it binds as one argument")
    eq(captured and captured.args.new, "y", "dispatch: ... and the next token is the next argument")
    ok(
      captured and not captured.flags.dry,
      "dispatch: ... and --dry inside the quote is not a flag"
    )

    captured = nil
    vim.cmd([[ComposerQuotesRunOn "a"b]])
    eq(captured and captured.args.old, "a", "dispatch: a quote closed mid-token ends the token")
    eq(captured and captured.args.new, "b", "dispatch: ... and what follows is the next argument")

    captured = nil
    vim.cmd([[ComposerQuotesRunOn "foo bar" --dry]])
    ok(captured and captured.flags.dry, "dispatch: a real flag after a quoted run is still a flag")

    captured, notes = nil, nil
    vim.cmd([[ComposerQuotesRunOff "x --dry" y]])
    ok(
      captured == nil,
      'dispatch: without `quotes` the blank split stays (flag `--dry"` is refused)'
    )
  end)
  vim.notify = real_notify
  if not dispatch_ok then
    error(dispatch_err, 0)
  end

  pcall(vim.api.nvim_del_user_command, "ComposerQuotesRunOn")
  pcall(vim.api.nvim_del_user_command, "ComposerQuotesRunOff")
  pcall(vim.api.nvim_del_user_command, "ComposerQuotesSpecOn")
  pcall(vim.api.nvim_del_user_command, "ComposerQuotesSpecOff")
end
