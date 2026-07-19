-- docs/TESTS/composer_spec.lua — lib.nvim.usercmd.composer
--
-- Covers the whole pipeline headlessly: tree build/walk, argument coercion,
-- the completion engine, dispatch (happy + error paths via an injected
-- synchronous notifier), custom types, and docgen (render + file round-trip).

return function(H)
  local eq, ok = H.eq, H.ok

  local composer = require("lib.nvim.usercmd.composer")
  local tree = require("lib.nvim.usercmd.composer.tree")
  local parse = require("lib.nvim.usercmd.composer.parse")
  local complete = require("lib.nvim.usercmd.composer.complete")
  local argtypes = require("lib.nvim.usercmd.composer.argtypes")
  local docgen = require("lib.nvim.usercmd.composer.docgen")

  -- Every internal + the aggregator path loads.
  for _, mod in ipairs({
    "lib.nvim.usercmd.composer", "lib.nvim.usercmd.composer.tree",
    "lib.nvim.usercmd.composer.parse", "lib.nvim.usercmd.composer.complete",
    "lib.nvim.usercmd.composer.argtypes", "lib.nvim.usercmd.composer.docgen",
    "lib.nvim.usercmd.composer.registry", "lib.nvim.usercmd.composer.format",
    "lib.nvim.usercmd.composer.flags",
  }) do
    ok(require(mod) ~= nil, "loads: " .. mod)
  end
  eq(type(require("lib").composer.verb), "function", "aggregator: lib.composer.verb wired")
  eq(type(require("lib").usercmd.composer.verb), "function", "aggregator: lib.usercmd.composer wired")

  -- ---------------------------------------------------------------- spec fixture
  ---@type Lib.UserCmd.Composer.Spec
  local spec = {
    desc = "Demo verb",
    default = function() return "DEFAULT" end,
    routes = {
      { path = { "buffer" }, desc = "on buffer", run = function() return "BUFFER" end },
      { path = { "count" }, args = { { name = "n", type = "INT" } },
        run = function(ctx) return ctx.args.n end },
      { path = { "cwd" }, args = { { name = "root", type = "STRING", optional = true, default = "HERE" } },
        run = function(ctx) return ctx.args.root end },
      { path = { "surround" },
        args = {
          { name = "kind", type = "STRING", enum = { "quote", "paren", "brace" } },
          { name = "target", type = "STRING" },
        },
        run = function(ctx) return ctx.args.kind .. "/" .. ctx.args.target end },
    },
  }
  local root = tree.build(spec.routes)

  -- ------------------------------------------------------------------ tree walk
  do
    local node, consumed = tree.walk(root, { "surround", "quote", "x" })
    eq(consumed, 1, "walk: consumes only the literal 'surround'")
    ok(node.route ~= nil, "walk: lands on the surround route")
    local n2, c2 = tree.walk(root, { "nope" })
    eq(c2, 0, "walk: unknown token consumes nothing")
    ok(n2.route == nil, "walk: unknown token stays at root (no route)")
  end

  -- ---------------------------------------------------------------- arg coercion
  do
    local okc, v = argtypes.validate("42", { name = "n", type = "INT" })
    ok(okc, "INT: '42' validates")
    eq(v, 42, "INT: coerces to number 42")
    eq(type(v), "number", "INT: result is a number, not a string")
    local bad = argtypes.validate("nope", { name = "n", type = "INT" })
    ok(not bad, "INT: 'nope' rejected")
    local eok, ev = argtypes.validate("Quote", { name = "k", enum = { "quote", "paren" } })
    ok(eok and ev == "quote", "enum: case-insensitive match normalizes to canonical value")
    ok(not (argtypes.validate("zzz", { name = "k", enum = { "quote" } })), "enum: non-member rejected")
    ok(argtypes.validate("anything", { name = "p", type = "STRING" }), "STRING: accepts any token")
  end

  -- ----------------------------------------------------------------- completion
  local function join(t) return table.concat(t, ",") end
  do
    local function comp(lead, line) return join(complete.candidates(root, lead, line)) end
    eq(comp("", "Demo "), "buffer,count,cwd,surround", "complete: root lists all subcommands, sorted")
    eq(comp("s", "Demo s"), "surround", "complete: prefix filter")
    eq(comp("", "Demo surround "), "quote,paren,brace", "complete: enum arg of surround")
    eq(comp("q", "Demo surround q"), "quote", "complete: enum arg prefix-filtered")
    eq(comp("", "Demo count "), "", "complete: INT arg has no candidates")
    eq(comp("", "Demo buffer "), "", "complete: no args past a leaf with no schema")
  end

  -- committed-token extraction (bang + trailing lead handling)
  do
    eq(join(complete.committed("Demo! surround ", "")), "surround", "committed: strips the command word incl. bang")
    eq(join(complete.committed("Demo surround qu", "qu")), "surround", "committed: drops the in-progress lead")
  end

  -- ------------------------------------------------------------------- dispatch
  -- Synchronous capture notifier so error paths are assertable inline.
  local msgs
  local cap = {
    error = function(m) msgs.error = m end,
    info = function(m) msgs.info = m end,
  }
  local function dispatch(fargs, extra)
    msgs = {}
    local opts = vim.tbl_extend("force", { fargs = fargs }, extra or {})
    return parse.dispatch("Demo", spec, root, opts, cap)
  end

  eq(dispatch({}), "DEFAULT", "dispatch: bare verb → default handler")
  eq(dispatch({ "buffer" }), "BUFFER", "dispatch: leaf route")
  eq(dispatch({ "count", "7" }), 7, "dispatch: INT arg coerced and passed")
  eq(dispatch({ "cwd" }), "HERE", "dispatch: omitted optional arg uses its default")
  eq(dispatch({ "cwd", "X" }), "X", "dispatch: provided optional arg wins")
  eq(dispatch({ "surround", "paren", "word" }), "paren/word", "dispatch: two positional args")

  dispatch({ "count" })
  ok(msgs.error and msgs.error:find("missing required argument"), "dispatch: missing required arg → error")
  dispatch({ "count", "nope" })
  ok(msgs.error and msgs.error:find("is not an integer"), "dispatch: bad INT → error with reason")
  dispatch({ "bogus" })
  ok(msgs.error and msgs.error:find("unknown subcommand 'bogus'"), "dispatch: unknown subcommand → error")

  -- ctx carries bang/range
  spec.routes[1].run = function(ctx) return ctx.bang end
  local rroot = tree.build(spec.routes)
  msgs = {}
  eq(parse.dispatch("Demo", spec, rroot, { fargs = { "buffer" }, bang = true }, cap), true,
    "dispatch: ctx.bang reflects the ! form")
  spec.routes[1].run = function() return "BUFFER" end -- restore

  -- ------------------------------------------------------------------- run resolution
  eq(parse.resolve_run(function() return 99 end)(), 99, "resolve_run: passes a function through")
  ok(parse.resolve_run("definitely.not.a.module") == nil, "resolve_run: bad module path → nil")

  -- ---------------------------------------------------------------- custom type
  composer.register_type("SHOUT", {
    validate = function(raw) return true, raw:upper(), nil end,
    complete = function() return { "loud", "louder" } end,
  })
  do
    local okc, v = argtypes.validate("hey", { name = "x", type = "SHOUT" })
    ok(okc and v == "HEY", "custom type: validate transforms the value")
    eq(join(argtypes.complete("", { name = "x", type = "SHOUT" })), "loud,louder", "custom type: completion")
  end

  -- ----------------------------------------------------------------------- docgen
  do
    local body = docgen.render({ { name = "Demo", spec = spec, root = root } })
    ok(body:find(":Demo surround {kind} {target}", 1, true), "docgen: renders full invocation")
    ok(body:find("`{kind}` ∈ `quote | paren | brace`", 1, true), "docgen: enum note")
    ok(body:find(":Demo cwd %[{root}%]"), "docgen: optional arg wrapped in [ ]")

    -- write round-trip
    local path = H.tmpfile(".md")
    local wok = docgen.write({ { name = "Demo", spec = spec, root = root } }, path, "replace")
    ok(wok, "docgen: write returns ok")
    local content = table.concat(H.read_lines(path), "\n")
    ok(content:find("## :Demo", 1, true), "docgen: file contains the verb section")

    -- section mode preserves surrounding prose
    local spath = H.tmpfile(".md")
    local f = io.open(spath, "w"); f:write("# Manual\n\nkeep me\n"); f:close()
    docgen.write({ { name = "Demo", spec = spec, root = root } }, spath, "section")
    local scontent = table.concat(H.read_lines(spath), "\n")
    ok(scontent:find("keep me", 1, true), "docgen section: preserves hand-written prose")
    ok(scontent:find("lib.nvim:composer", 1, true), "docgen section: inserts the delimited block")
  end

  -- --------------------------------------------------------------- flags (Phase 6)
  local flags = require("lib.nvim.usercmd.composer.flags")

  -- A route WITHOUT declared flags: "--" tokens must NOT be treated specially
  -- (backward-compat guarantee — every pre-Phase-6 route keeps working as-is).
  local no_flags_route = { path = { "x" }, args = { { name = "a", type = "STRING" } } }
  do
    local p, f, err = flags.split(no_flags_route, { "--looks-like-a-flag" })
    eq(err, nil, "flags.split: no declared flags -> no error, ever")
    eq(#p, 1, "flags.split: no declared flags -> tokens pass through untouched")
    eq(p[1], "--looks-like-a-flag", "flags.split: '--' token treated as an ordinary positional")
    eq(next(f), nil, "flags.split: no declared flags -> empty flags table")
  end

  local flag_route = {
    path = {},
    args = { { name = "old", type = "STRING" }, { name = "new", type = "STRING" } },
    flags = {
      { name = "dry", bool = true },
      { name = "type", type = "STRING", repeatable = true },
      { name = "engine", type = "STRING", enum = { "fzf", "telescope" } },
    },
  }

  do
    -- bool flag, inline =value, space-separated value, repeatable collection
    local p, f = flags.split(flag_route, { "foo", "bar", "--dry", "--type=lua", "--type", "go", "--engine=fzf" })
    eq(table.concat(p, ","), "foo,bar", "flags.split: positionals extracted in order, flags removed")
    eq(f.dry, true, "flags.split: bool flag present -> true")
    eq(table.concat(f.type, ","), "lua,go", "flags.split: repeatable flag collects every occurrence, mixing =value and space-separated forms")
    eq(f.engine, "fzf", "flags.split: enum-valued flag coerced")
  end

  do
    -- flags may appear anywhere, including before positionals
    local p, f = flags.split(flag_route, { "--dry", "foo", "bar" })
    eq(table.concat(p, ","), "foo,bar", "flags.split: flag before positionals doesn't disturb positional order")
    eq(f.dry, true, "flags.split: flag-first form works")
  end

  do
    -- literal "--" stops flag parsing; everything after is positional even if flag-shaped
    local p, f = flags.split(flag_route, { "foo", "--", "--dry", "bar" })
    eq(table.concat(p, ","), "foo,--dry,bar", "flags.split: bare -- stops flag parsing (replacer.nvim's flags_done sentinel)")
    eq(f.dry, nil, "flags.split: --dry after the -- sentinel is NOT parsed as a flag")
  end

  do
    local _, _, err = flags.split(flag_route, { "foo", "bar", "--bogus" })
    ok(err and err:find("unknown flag"), "flags.split: undeclared flag -> error, not silently positional")
    local _, _, err2 = flags.split(flag_route, { "foo", "bar", "--type" }) -- value-flag with nothing after it
    ok(err2 and err2:find("requires a value"), "flags.split: value flag with no following token -> error")
    local bool_route = { path = {}, flags = { { name = "dry", bool = true } } }
    local _, _, err3 = flags.split(bool_route, { "--dry=yes" })
    ok(err3 and err3:find("takes no value"), "flags.split: bool flag given =value -> error")
  end

  do
    -- default applied only when the flag was never passed
    local defaulted = { path = {}, flags = { { name = "context", type = "INT", default = 3 } } }
    local _, f = flags.split(defaulted, {})
    eq(f.context, 3, "flags.split: unpassed flag with a default gets it")
    local _, f2 = flags.split(defaulted, { "--context=7" })
    eq(f2.context, 7, "flags.split: passed value overrides the default")
  end

  -- ctx.flags reaches the handler through full dispatch
  do
    local seen
    local spec_with_flags = {
      routes = { vim.tbl_extend("force", flag_route, {
        run = function(ctx) seen = ctx.flags end,
      }) },
    }
    local root = tree.build(spec_with_flags.routes)
    parse.dispatch("FlagsCtx", spec_with_flags, root,
      { fargs = { "a", "b", "--dry" } }, cap)
    ok(seen and seen.dry == true, "dispatch: ctx.flags is populated end-to-end")
  end

  -- flags.strip: lenient, used by completion to not miscount positional slots
  do
    eq(join(flags.strip(flag_route, { "--dry", "foo" })), "foo", "flags.strip: bool flag stripped, no value token consumed")
    eq(join(flags.strip(flag_route, { "--type", "lua", "foo" })), "foo", "flags.strip: value flag AND its value token both stripped")
    eq(join(flags.strip(no_flags_route, { "--x" })), "--x", "flags.strip: no declared flags -> passthrough (matches split's backward-compat)")
  end

  -- flags.candidates / completion integration
  do
    local names = flags.candidates(flag_route, "--")
    table.sort(names)
    eq(table.concat(names, ","), "--dry,--engine,--type", "flags.candidates: full --name form, sorted")
    eq(join(flags.candidates(flag_route, "--e")), "--engine", "flags.candidates: prefix filter")
    local vals = flags.candidates(flag_route, "--engine=")
    table.sort(vals)
    eq(table.concat(vals, ","), "--engine=fzf,--engine=telescope", "flags.candidates: enum value completion, full replacement strings")
    eq(join(flags.candidates(flag_route, "--dry=")), "", "flags.candidates: bool flag has no value completion")
    eq(join(flags.candidates(no_flags_route, "--")), "", "flags.candidates: no declared flags -> no candidates")
  end

  -- end-to-end completion: flag-name and enum-value slots on a real route tree
  do
    local root = tree.build({ vim.tbl_extend("force", flag_route, { run = function() end }) })
    local function comp(lead, line) return complete.candidates(root, lead, line) end
    local top = comp("--e", "FlagsComp --e")
    eq(join(top), "--engine", "complete.candidates: flag-name completion routed through the engine")
    local vals = comp("--engine=", "FlagsComp --engine=")
    table.sort(vals)
    eq(table.concat(vals, ","), "--engine=fzf,--engine=telescope", "complete.candidates: flag-value completion routed through the engine")
  end

  -- docgen renders flags in the invocation + enum notes
  do
    local root = tree.build({ vim.tbl_extend("force", flag_route, { run = function() end }) })
    local body = docgen.render({ { name = "FlagsDoc", spec = { routes = { flag_route } }, root = root } })
    ok(body:find("[--dry]", 1, true), "docgen: bool flag rendered as [--dry]")
    ok(body:find("[--type=<value> ...]", 1, true), "docgen: repeatable value flag rendered with trailing ...")
    ok(body:find("[--engine=<fzf|telescope>]", 1, true), "docgen: enum flag renders its member list inline")
    ok(body:find("`--engine` ∈ `fzf | telescope`", 1, true), "docgen: enum flag gets its own note line")
  end

  -- ------------------------------------------------------- end-to-end registration
  do
    local fired
    composer.verb("ComposerSpecE2E", {
      routes = {
        { path = { "go" }, args = { { name = "n", type = "INT" } },
          run = function(ctx) fired = ctx.args.n end },
      },
    })
    vim.cmd("ComposerSpecE2E go 5")
    eq(fired, 5, "e2e: real :command registration dispatches and coerces")
    -- completion callback is wired on the real command
    local cc = vim.fn.getcompletion("ComposerSpecE2E ", "cmdline")
    ok(vim.tbl_contains(cc, "go"), "e2e: cmdline completion offers the subcommand")
    pcall(vim.api.nvim_del_user_command, "ComposerSpecE2E")
  end

  -- route.range must reach the real :command registration (wants_range),
  -- not just spec.range -- a route declaring `range = true` with no
  -- verb-level spec.range previously registered a range-less command.
  -- (Invoking a live range like `:1,2Cmd` from vim.cmd is a separate,
  -- pre-existing Neovim quirk unrelated to composer -- reproduces even for
  -- a bare `:command -range Foo` + `:1,2Foo`, so range plumbing is checked
  -- via the registered command's metadata + a direct dispatch call instead,
  -- the same approach the bang test above already uses.)
  do
    composer.verb("ComposerSpecRange", {
      routes = {
        { path = { "go" }, range = true, run = function() end },
      },
    })
    local def = vim.api.nvim_get_commands({})["ComposerSpecRange"]
    ok(def and def.range and def.range ~= "" and def.range ~= false,
      "route.range=true propagates to the real user command (wants_range)")
    pcall(vim.api.nvim_del_user_command, "ComposerSpecRange")
  end

  do
    local captured
    local spec_range = {
      routes = { { path = { "go" }, range = true, run = function(ctx) captured = ctx.range end } },
    }
    local root2 = tree.build(spec_range.routes)
    parse.dispatch("ComposerSpecRange2", spec_range, root2,
      { fargs = { "go" }, range = 2, line1 = 5, line2 = 9 }, cap)
    eq(captured.range, 2, "ctx.range.range reaches the handler")
    eq(captured.line1, 5, "ctx.range.line1 reaches the handler")
    eq(captured.line2, 9, "ctx.range.line2 reaches the handler")
  end
end
