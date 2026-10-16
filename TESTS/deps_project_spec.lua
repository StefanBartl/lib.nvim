-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/deps_project_spec.lua -- lib.nvim.deps.project (+ its Mason adapter) and
-- the two parser_policy entry points it is built on (`status`, `install`).
--
-- Everything outside the module under test is stubbed through `package.loaded`
-- (`nvim-treesitter`, `mason-registry`) or `H.with_patched`, so the spec reads
-- the same on a CI container and on a machine with a full plugin set. The
-- directory scans run against a real temp tree; installs never run -- the
-- callees (`parser_policy.install`, `deps.install.run`, the Mason adapter) are
-- replaced by recorders, because "did it ASK first, and did it hand over
-- exactly this" is the contract.

return function(H)
  local eq, ok = H.eq, H.ok

  local policy = require("lib.nvim.treesitter.parser_policy")
  local project = require("lib.nvim.deps.project")
  local mason = require("lib.nvim.deps.project.mason")
  local deps_install = require("lib.nvim.deps.install")
  local pm = require("lib.nvim.deps.pm")
  local collect = require("lib.nvim.fs.collect_recursive")

  -- Invented filetypes: whether `rust` has a parser on runtimepath depends on the
  -- machine running the spec, `zzra` never does. The names are language names too
  -- (`get_lang` answers the filetype itself when nothing is registered).
  vim.filetype.add({ extension = { zzra = "zzra", zzgo = "zzgo" } })

  ---Run `fn` with `package.loaded[name]` replaced (nil removes it, and a
  ---preload that raises keeps `require` from finding the real one), then
  ---put everything back whatever happens.
  ---@param name string
  ---@param value any
  ---@param fn fun()
  local function with_module(name, value, fn)
    local old_loaded, old_preload = package.loaded[name], package.preload[name]
    package.loaded[name] = value
    if value == nil then
      package.preload[name] = function()
        error("module '" .. name .. "' is absent in this test")
      end
    end
    local ok_run, err = pcall(fn)
    package.loaded[name] = old_loaded
    package.preload[name] = old_preload
    if not ok_run then
      error(err, 0)
    end
  end

  ---A stand-in for `nvim-treesitter`.
  ---@param installed string[]
  ---@param available string[]
  ---@param install_calls? string[][] receives the arguments of every `install`
  ---@param tasks? table[] receives every returned task (to finish them by hand)
  local function fake_ts(installed, available, install_calls, tasks)
    return {
      get_installed = function()
        return installed
      end,
      get_available = function()
        return available
      end,
      install = function(langs)
        if install_calls then
          install_calls[#install_calls + 1] = langs
        end
        local task = {
          await = function(self, cb)
            self.finish = cb
          end,
        }
        if tasks then
          tasks[#tasks + 1] = task
        end
        return task
      end,
    }
  end

  ---Block (vim.wait) until `start(done)` calls `done`; returns its arguments.
  ---@param start fun(done: fun(...))
  ---@return any ...
  local function await(start)
    local finished, results = false, nil
    start(function(...)
      results = { ... }
      finished = true
    end)
    ok(
      vim.wait(5000, function()
        return finished
      end, 5),
      "await: the async call finished within its timeout"
    )
    return unpack(results)
  end

  ---@param path string
  ---@param text? string
  local function touch(path, text)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "w"))
    f:write(text or "x")
    f:close()
  end

  ---A temp tree with files `names` (relative paths).
  ---@param names string[]
  ---@return string root
  local function tree(names)
    local root = vim.fn.tempname() .. "_dpscan"
    vim.fn.mkdir(root, "p")
    for _, name in ipairs(names) do
      touch(root .. "/" .. name)
    end
    return vim.fs.normalize(root)
  end

  -- ------------------------------------------------- parser_policy.status
  do
    local ts = fake_ts({ "lua" }, { "lua", "zzra", "zzpy" })
    with_module("nvim-treesitter", ts, function()
      eq(policy.status("zzra"), "available", "status: listed by nvim-treesitter, not installed")
      eq(policy.status("lua"), "installed", "status: listed as installed")
      eq(policy.status("zz_no_such_lang"), "unavailable", "status: unknown to nvim-treesitter")
      eq(policy.status(""), "unavailable", "status: empty name")
      eq(policy.status(nil), "unavailable", "status: not a string")
    end)

    with_module("nvim-treesitter", nil, function()
      eq(policy.status("zz_no_such_lang"), "unknown", "status: nvim-treesitter not loadable")
    end)

    -- A parser library on runtimepath counts as installed even when
    -- nvim-treesitter never heard of it (the bundled parsers are like this).
    local dir = vim.fn.tempname() .. "_rtp"
    touch(dir .. "/parser/zz_fake_lang.so")
    local old_rtp = vim.o.runtimepath
    vim.opt.runtimepath:append(dir)
    local ok_run, err = pcall(function()
      with_module("nvim-treesitter", fake_ts({}, { "zz_fake_lang" }), function()
        eq(
          policy.status("zz_fake_lang"),
          "installed",
          "status: a parser/<lang>.* library on runtimepath is installed"
        )
      end)
      with_module("nvim-treesitter", nil, function()
        eq(
          policy.status("zz_fake_lang"),
          "installed",
          "status: runtimepath is enough even without nvim-treesitter"
        )
      end)
    end)
    vim.o.runtimepath = old_rtp
    vim.fn.delete(dir, "rf")
    if not ok_run then
      error(err, 0)
    end
  end

  -- ------------------------------------------------- parser_policy.install
  do
    local calls, tasks = {}, {}
    with_module("nvim-treesitter", fake_ts({ "lua" }, { "lua", "zzra" }, calls, tasks), function()
      local old_mode = policy.get_mode()
      policy.set_mode("off")

      local done = {}
      eq(
        policy.install("zzra", function(lang)
          done[#done + 1] = lang
        end),
        true,
        "install: an available parser starts, even in mode off (the caller asked)"
      )
      eq(#calls, 1, "install: nvim-treesitter's install ran once")
      eq(calls[1][1], "zzra", "install: for that language")
      eq(
        policy.install("zzra"),
        false,
        "install: the same language while it is installing is refused"
      )
      eq(#calls, 1, "install: no second install started")

      tasks[1].finish(nil)
      eq(done[1], "zzra", "install: on_installed fires after a successful install")
      eq(policy.install("lua"), false, "install: an installed parser is not reinstalled")
      eq(policy.install("zz_no_such_lang"), false, "install: an unknown parser is refused")
      eq(policy.install(""), false, "install: an empty name is refused")
      eq(#calls, 1, "install: refusals start nothing")

      policy.set_mode(old_mode)
    end)
  end

  -- ------------------------------------------------------------- key_of
  do
    eq(project.key_of("/a/b/Foo.LUA"), "*.lua", "key_of: extension, lower-cased")
    eq(project.key_of("C:\\a\\b\\c.tar.gz"), "*.gz", "key_of: last extension, backslash path")
    eq(project.key_of("/a/Makefile"), "Makefile", "key_of: no extension -> the name")
    eq(project.key_of("/a/.gitignore"), ".gitignore", "key_of: a leading dot is not an extension")
    eq(project.key_of("/a/noext."), "noext.", "key_of: a trailing dot is not an extension")
  end

  -- -------------------------------------------------------------- count
  do
    local scan = project.count("/r/", { "/r/a.lua", "/r/b.LUA", "/r/Makefile", "/r/c/d.zzra" })
    eq(scan.total, 4, "count: total")
    eq(scan.keys["*.lua"].count, 2, "count: two lua files, case-folded")
    eq(scan.keys["*.lua"].sample, "/r/a.lua", "count: the sample is the first path of the kind")
    eq(scan.keys["Makefile"].count, 1, "count: extensionless name")
    eq(scan.root, "/r", "count: trailing slash dropped from the root")
  end

  -- --------------------------------------------------------------- scan
  do
    local root = tree({
      "a.lua",
      "b.lua",
      "sub/c.zzra",
      "Makefile",
      "node_modules/dep/x.js",
      ".git/config",
      "target/debug/y.zzra",
    })
    project.forget()

    local scan = await(function(done)
      project.scan(root, nil, done)
    end)
    eq(scan.total, 4, "scan: ignored directories (.git, node_modules, target) are not walked")
    eq(scan.keys["*.lua"].count, 2, "scan: counts per extension")
    eq(scan.keys["*.zzra"].count, 1, "scan: nested files are counted, the ignored target/ one not")
    eq(scan.keys["*.js"], nil, "scan: node_modules content does not appear")

    -- Cache: a file added afterwards is invisible until refresh.
    touch(root .. "/late.lua")
    local again = await(function(done)
      project.scan(root, nil, done)
    end)
    eq(again.keys["*.lua"].count, 2, "scan: within the TTL the cached answer is served")
    local fresh = await(function(done)
      project.scan(root, { refresh = true }, done)
    end)
    eq(fresh.keys["*.lua"].count, 3, "scan: refresh walks again")
    local expired = await(function(done)
      touch(root .. "/later.lua")
      project.scan(root, { ttl_seconds = 0 }, done)
    end)
    eq(expired.keys["*.lua"].count, 4, "scan: a zero TTL never trusts the cache")

    -- One walk for two callers of the same root.
    project.forget()
    local walks = 0
    local real = collect.files_async
    H.with_patched(collect, "files_async", function(...)
      walks = walks + 1
      return real(...)
    end, function()
      local first, second
      project.scan(root, nil, function(s)
        first = s
      end)
      project.scan(root, nil, function(s)
        second = s
      end)
      ok(
        vim.wait(5000, function()
          return first ~= nil and second ~= nil
        end, 5),
        "scan: both callers are answered"
      )
      eq(walks, 1, "scan: two callers of one root share one walk")
      eq(first, second, "scan: and receive the same result")
    end)

    -- A walk that could not read a directory is delivered, not cached.
    project.forget()
    local attempts = 0
    H.with_patched(collect, "files_async", function(_, _, on_done)
      attempts = attempts + 1
      vim.schedule(function()
        on_done({ root .. "/a.lua" }, { root .. "/locked: permission denied" })
      end)
      return function() end
    end, function()
      local partial = await(function(done)
        project.scan(root, nil, done)
      end)
      eq(partial.errors[1], root .. "/locked: permission denied", "scan: errors are delivered")
      await(function(done)
        project.scan(root, nil, done)
      end)
      eq(attempts, 2, "scan: a partial walk is not cached")
    end)

    -- Cancel: the callback never fires.
    project.forget()
    local fired = false
    local cancel = project.scan(root, nil, function()
      fired = true
    end)
    cancel()
    vim.wait(200, function()
      return false
    end, 20)
    eq(fired, false, "scan: a cancelled wait is never called back")

    vim.fn.delete(root, "rf")
    project.forget()
  end

  -- -------------------------------------------------------------- report
  ---@param paths string[]
  local function scan_of(paths)
    return project.count("/proj", paths)
  end

  ---@param owner string
  ---@param map table
  ---@param fn fun()
  local function with_tools(owner, map, fn)
    local unregister = project.register_tools(owner, map)
    local ok_run, err = pcall(fn)
    unregister()
    if not ok_run then
      error(err, 0)
    end
  end

  local PRESENT_BIN = { bin = "nvim", why = "the editor itself, present on every test host" }
  local MISSING_BIN = {
    bin = "zz-definitely-not-a-binary",
    why = "A tool that cannot exist on any host.",
    pkg = { brew = "zz-ghost" },
  }

  do
    local paths = {
      "/proj/a.zzra",
      "/proj/b.zzra",
      "/proj/c.zzra",
      "/proj/a.zzgo",
      "/proj/a.lua",
      "/proj/Makefile",
      "/proj/readme.zzzunknownext",
    }
    local ts = fake_ts({ "lua" }, { "lua", "zzra", "zzgo" })
    with_module("nvim-treesitter", ts, function()
      local report = project.report(scan_of(paths), { registered = false })

      eq(report.total, 7, "report: total carried over")
      eq(report.unmapped, 1, "report: the file of unknown filetype is counted as unmapped")
      eq(report.languages[1].lang, "zzra", "report: languages sorted by files, most first")
      eq(report.languages[1].files, 3, "report: files per language")
      eq(report.languages[1].state, "available", "report: installable, not installed")

      local missing = {}
      for _, entry in ipairs(report.missing_parsers) do
        missing[#missing + 1] = entry.lang
      end
      table.sort(missing)
      eq(
        table.concat(missing, ","),
        "zzgo,zzra",
        "report: missing = installable and not installed (lua is installed, make has no parser)"
      )

      -- "Never" is reported as such, not as installable.
      H.with_patched(policy, "declined", function()
        return { "zzgo" }
      end, function()
        local r = project.report(scan_of(paths), { registered = false })
        local states = {}
        for _, entry in ipairs(r.missing_parsers) do
          states[entry.lang] = entry.state
        end
        eq(states.zzgo, "declined", "report: a language answered with Never is 'declined'")
        eq(states.zzra, "available", "report: the others stay installable")
      end)

      -- No nvim-treesitter at all: nothing can be called missing.
      with_module("nvim-treesitter", nil, function()
        local r = project.report(scan_of({ "/proj/a.zzfake_rs" }), { registered = false })
        eq(#r.missing_parsers, 0, "report: unknown parser state is not 'missing'")
      end)
    end)
  end

  -- tools ---------------------------------------------------------------
  do
    local registry = {
      installed = { ["stylua"] = true },
      known = { ["stylua"] = true, ["rust-analyzer"] = true },
    }
    local fake_registry = {
      get_package = function(name)
        if not registry.known[name] then
          error("Cannot find package " .. name)
        end
        return {
          is_installed = function()
            return registry.installed[name] == true
          end,
        }
      end,
    }

    local paths = { "/proj/a.zzra", "/proj/b.zzra", "/proj/c.lua" }
    with_module("nvim-treesitter", fake_ts({ "lua", "zzra" }, { "lua", "zzra" }), function()
      with_module("mason-registry", fake_registry, function()
        local map = {
          zzra = { MISSING_BIN, { mason = "rust-analyzer" }, { mason = "stylua" } },
          lua = { MISSING_BIN, PRESENT_BIN, { mason = "typo-package" } },
          zzpy = { { bin = "never-asked-for-python" } },
        }
        with_tools("spec-owner", map, function()
          local report = project.report(scan_of(paths))
          local by_id = {}
          for _, status in ipairs(report.tools) do
            by_id[status.kind .. ":" .. status.id] = status
          end

          ok(
            by_id["bin:never-asked-for-python"] == nil,
            "report: tools of a filetype that is not in the root are not reported"
          )
          local shared = by_id["bin:zz-definitely-not-a-binary"]
          eq(shared.state, "missing", "report: absent bin tool is missing")
          eq(#shared.filetypes, 2, "report: one tool wanted by two filetypes is listed once")
          eq(shared.files, 3, "report: with the files of both filetypes summed")
          eq(by_id["bin:nvim"].state, "present", "report: present bin tool")
          eq(by_id["mason:rust-analyzer"].state, "missing", "report: known, not installed")
          eq(by_id["mason:stylua"].state, "present", "report: installed Mason package")
          eq(by_id["mason:typo-package"].state, "unavailable", "report: unknown to the registry")

          local missing = {}
          for _, status in ipairs(report.missing_tools) do
            missing[#missing + 1] = status.id
          end
          table.sort(missing)
          eq(
            table.concat(missing, ","),
            "rust-analyzer,zz-definitely-not-a-binary",
            "report: missing_tools is exactly the state == missing subset"
          )

          -- registered=false ignores the registry; opts.tools (also as a function) adds.
          local bare = project.report(scan_of(paths), { registered = false })
          eq(#bare.tools, 0, "report: registered = false ignores register_tools")
          local fn_tools = project.report(scan_of(paths), {
            registered = false,
            tools = function()
              return { zzra = { { bin = "zz-from-function" } } }
            end,
          })
          eq(fn_tools.tools[1].id, "zz-from-function", "report: opts.tools may be a function")
        end)

        -- Unusable entries are named, not swallowed.
        with_tools("bad-owner", { zzra = { { why = "no bin, no mason" }, "nope" } }, function()
          local report = project.report(scan_of(paths))
          eq(#report.problems, 2, "report: two unusable entries -> two problems")
          ok(report.problems[1]:find("zzra", 1, true), "report: a problem names its filetype")
        end)
      end)

      with_module("mason-registry", nil, function()
        local r = project.report(scan_of(paths), {
          registered = false,
          tools = { zzra = { { mason = "rust-analyzer" } } },
        })
        eq(r.tools[1].state, "unknown", "report: Mason not loadable -> unknown, not missing")
        eq(#r.missing_tools, 0, "report: and therefore not offered")
      end)
    end)

    -- register_tools bookkeeping
    local un = project.register_tools("zz-owner-b", {})
    local un2 = project.register_tools("zz-owner-a", {})
    eq(
      table.concat(project.registered(), ","),
      "zz-owner-a,zz-owner-b",
      "register_tools: owners are listed sorted"
    )
    un()
    un2()
    eq(#project.registered(), 0, "register_tools: the returned function unregisters")
  end

  -- --------------------------------------------------------- lines / summary
  do
    local paths = { "/proj/a.zzra", "/proj/b.zzra" }
    with_module("nvim-treesitter", fake_ts({}, { "zzra" }), function()
      with_module("mason-registry", nil, function()
        local report = project.report(scan_of(paths), {
          registered = false,
          tools = { zzra = { MISSING_BIN, { bin = "zz-no-brew-pkg", pkg = { apt = "x" } } } },
        })
        local text = table.concat(project.lines(report, { manager = pm.get("brew") }), "\n")
        ok(
          text:find("No brew package is declared for: zz-no-brew-pkg", 1, true),
          "lines: a missing tool the host's manager has no package for is named"
        )
        ok(text:find("Treesitter parsers not installed", 1, true), "lines: parser section")
        ok(text:find("- zzra  (zzra, 2 files)", 1, true), "lines: language, filetype and files")
        ok(text:find("zz-definitely-not-a-binary", 1, true), "lines: the missing tool")
        ok(text:find("A tool that cannot exist on any host.", 1, true), "lines: its why")
        ok(text:find("brew install zz-ghost", 1, true), "lines: the install command")
        ok(text:find(":Lib deps project install", 1, true), "lines: how to install")

        local summary = project.summary(report)
        ok(summary:find("parsers: zzra", 1, true), "summary: names the parsers")
        ok(summary:find("tools: zz-definitely-not-a-binary", 1, true), "summary: and the tools")
      end)
    end)

    with_module("nvim-treesitter", fake_ts({ "zzra" }, { "zzra" }), function()
      local report = project.report(scan_of(paths), { registered = false })
      eq(project.summary(report), nil, "summary: nil when nothing is missing")
      local text = table.concat(project.lines(report), "\n")
      ok(text:find("Nothing missing", 1, true), "lines: says so when nothing is missing")
    end)
  end

  -- ---------------------------------------------------------- install_plan
  local function missing_report()
    local paths = { "/proj/a.zzra", "/proj/a.zzgo", "/proj/c.lua" }
    return project.report(scan_of(paths), {
      registered = false,
      tools = {
        zzra = { MISSING_BIN, { mason = "rust-analyzer" } },
      },
    })
  end

  do
    local fake_registry = {
      get_package = function()
        return {
          is_installed = function()
            return false
          end,
        }
      end,
    }
    with_module("nvim-treesitter", fake_ts({ "lua" }, { "lua", "zzra", "zzgo" }), function()
      with_module("mason-registry", fake_registry, function()
        H.with_patched(policy, "declined", function()
          return { "zzgo" }
        end, function()
          local plan = project.install_plan(missing_report(), { manager = pm.get("brew") })
          eq(
            table.concat(plan.parsers, ","),
            "zzra",
            "install_plan: parsers without the Never ones"
          )
          eq(table.concat(plan.declined, ","), "zzgo", "install_plan: the Never ones are named")
          eq(table.concat(plan.mason, ","), "rust-analyzer", "install_plan: Mason packages")
          eq(#plan.tools, 1, "install_plan: bin tools")
          eq(
            plan.plan.commands[1][#plan.plan.commands[1]],
            "zz-ghost",
            "install_plan: via deps.install"
          )
          eq(plan.empty, false, "install_plan: not empty")
          ok(plan.text:find("rust-analyzer", 1, true), "install_plan: the question lists Mason")
          ok(plan.text:find("brew install zz-ghost", 1, true), "install_plan: and the command")
          ok(
            plan.text:find("typed into a terminal", 1, true),
            "install_plan: and that it is not run"
          )
          ok(plan.text:find("zzgo", 1, true), "install_plan: and what was left out")
        end)

        local empty =
          project.install_plan(project.report(scan_of({ "/proj/c.lua" }), { registered = false }))
        eq(empty.empty, true, "install_plan: nothing missing -> empty")
      end)
    end)
  end

  -- ---------------------------------------------------------------- install
  do
    local fake_registry = {
      get_package = function()
        return {
          is_installed = function()
            return false
          end,
        }
      end,
    }
    with_module("nvim-treesitter", fake_ts({ "lua" }, { "lua", "zzra" }), function()
      with_module("mason-registry", fake_registry, function()
        local report = missing_report()

        local parsers, masons, runs = {}, {}, {}
        local asked = {}
        local function recorders(answer, body)
          H.with_patched(policy, "install", function(lang)
            parsers[#parsers + 1] = lang
            return true
          end, function()
            H.with_patched(mason, "install", function(names)
              for _, name in ipairs(names) do
                masons[#masons + 1] = name
              end
            end, function()
              H.with_patched(deps_install, "run", function(plan, opts)
                runs[#runs + 1] = { plan = plan, opts = opts }
                return true
              end, function()
                H.with_patched(vim.fn, "confirm", function(text)
                  asked[#asked + 1] = text
                  return answer
                end, body)
              end)
            end)
          end)
        end

        -- Cancel: asked, nothing started.
        recorders(2, function()
          local started = project.install(report, { manager = pm.get("brew") })
          eq(started, nil, "install: cancelled -> nil")
        end)
        eq(#asked, 1, "install: asks exactly once before doing anything")
        ok(asked[1]:find("zzra", 1, true), "install: the question names the parser")
        eq(#parsers + #masons + #runs, 0, "install: cancelled starts nothing")

        -- Yes: all three ways, with the terminal one unconfirmed a second time.
        asked = {}
        recorders(1, function()
          local started = project.install(report, { manager = pm.get("brew") })
          eq(table.concat(started.parsers, ","), "zzra", "install: parsers started")
          eq(table.concat(started.mason, ","), "rust-analyzer", "install: Mason packages started")
          eq(started.terminal, true, "install: terminal handoff started")
        end)
        eq(table.concat(parsers, ","), "zzra", "install: parser_policy.install got the language")
        eq(table.concat(masons, ","), "rust-analyzer", "install: the Mason adapter got the package")
        eq(#runs, 1, "install: one terminal handoff")
        eq(runs[1].opts.confirm, false, "install: deps.install is not asked a second time")
        eq(runs[1].plan.commands[1][#runs[1].plan.commands[1]], "zz-ghost", "install: its command")
        eq(#asked, 1, "install: still one question in total")

        -- confirm = false: no question, same work.
        asked, parsers, masons, runs = {}, {}, {}, {}
        recorders(2, function()
          project.install(report, { confirm = false, manager = pm.get("brew") })
        end)
        eq(#asked, 0, "install: confirm = false skips the question")
        eq(#parsers, 1, "install: and still installs")

        -- Nothing missing: no question.
        asked = {}
        recorders(1, function()
          local none =
            project.install(project.report(scan_of({ "/proj/c.lua" }), { registered = false }))
          eq(none, nil, "install: nothing missing -> nil")
        end)
        eq(#asked, 0, "install: nothing missing -> nothing asked")
      end)
    end)
  end

  -- ------------------------------------------------------------ mason adapter
  do
    local state = { refreshed = 0, installs = {}, installing = {}, installed = {}, known = {} }
    local function package(name)
      return {
        is_installed = function()
          return state.installed[name] == true
        end,
        is_installing = function()
          return state.installing[name] == true
        end,
        install = function(_, opts, cb)
          state.installs[#state.installs + 1] = { name = name, opts = opts, cb = cb }
          return {}
        end,
      }
    end
    local fake_registry = {
      refresh = function(cb)
        state.refreshed = state.refreshed + 1
        cb(true, {})
      end,
      get_package = function(name)
        if not state.known[name] then
          error("Cannot find package " .. name)
        end
        return package(name)
      end,
    }
    state.known = { a = true, b = true, busy = true, done = true }
    state.installing.busy = true
    state.installed.done = true

    with_module("mason-registry", fake_registry, function()
      eq(mason.available(), true, "mason: available when the registry loads")
      eq(mason.status("a"), "missing", "mason.status: known, not installed")
      eq(mason.status("done"), "present", "mason.status: installed")
      eq(mason.status("nope"), "unavailable", "mason.status: the registry does not know it")

      local each, final = {}, nil
      mason.install({ "a", "b", "busy", "done", "nope" }, function(name, success, err)
        each[name] = { ok = success, err = err }
      end, function(results)
        final = results
      end)
      ok(
        vim.wait(2000, function()
          return each.busy ~= nil and each.done ~= nil and each.nope ~= nil
        end, 5),
        "mason.install: refusals are reported"
      )
      eq(state.refreshed, 1, "mason.install: refreshes the registry once first")
      eq(#state.installs, 2, "mason.install: only the two installable packages are started")
      eq(each.busy.err, "already installing", "mason.install: busy package reported")
      eq(each.done.err, "already installed", "mason.install: installed package reported")
      eq(each.nope.err, "not in the Mason registry", "mason.install: unknown package reported")
      eq(final, nil, "mason.install: not done while installs are running")

      state.installs[1].cb(true)
      state.installs[2].cb(false, "boom")
      ok(
        vim.wait(2000, function()
          return final ~= nil
        end, 5),
        "mason.install: on_done fires after the last package"
      )
      eq(each.a.ok, true, "mason.install: success reported")
      eq(each.b.ok, false, "mason.install: failure reported")
      eq(each.b.err, "boom", "mason.install: with the reason")
      eq(final.a, true, "mason.install: results table")
    end)

    with_module("mason-registry", nil, function()
      eq(mason.available(), false, "mason: unavailable without the registry")
      eq(mason.status("a"), "unknown", "mason.status: unknown without Mason")
      local result
      mason.install({ "a" }, nil, function(results)
        result = results
      end)
      ok(
        vim.wait(2000, function()
          return result ~= nil
        end, 5),
        "mason.install: without Mason it still answers"
      )
      eq(result.a, false, "mason.install: and says no")
    end)
  end

  -- ----------------------------------------------------------------- trigger
  do
    local root = tree({ "x.zzra", "y.zzra" })
    local notify_mod = require("lib.nvim.notify")
    local infos = {}
    local stub = {
      info = function(msg)
        infos[#infos + 1] = msg
      end,
      warn = function() end,
      error = function() end,
      debug = function() end,
    }
    project.forget()
    project.reset_announced()

    with_module("nvim-treesitter", fake_ts({}, { "zzra" }), function()
      H.with_patched(notify_mod, "create", function()
        return stub
      end, function()
        local old_cwd = vim.fn.getcwd()
        vim.cmd("cd " .. vim.fn.fnameescape(root))

        project.setup({ auto = true })
        local groups = vim.api.nvim_get_autocmds({ group = "lib.nvim.deps.project" })
        eq(#groups, 1, "setup: one DirChanged autocmd")
        eq(groups[1].event, "DirChanged", "setup: it is DirChanged")
        ok(
          vim.wait(5000, function()
            return #infos >= 1
          end, 5),
          "setup: the current directory is checked at once"
        )
        ok(infos[1]:find("parsers: zzra", 1, true), "setup: the summary names what is missing")

        -- Same root again: same summary, no second announcement.
        vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global" })
        vim.wait(300, function()
          return false
        end, 20)
        eq(#infos, 1, "setup: an unchanged root is announced once")

        project.reset_announced()
        vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global" })
        ok(
          vim.wait(5000, function()
            return #infos >= 2
          end, 5),
          "setup: after reset_announced it is announced again"
        )

        project.setup({})
        eq(
          pcall(vim.api.nvim_get_autocmds, { group = "lib.nvim.deps.project" }),
          false,
          "setup: without auto the trigger is gone"
        )

        vim.cmd("cd " .. vim.fn.fnameescape(old_cwd))
      end)
    end)

    project.reset_announced()
    project.forget()
    vim.fn.delete(root, "rf")
  end

  -- -------------------------------------------------------------------- run
  do
    local root = tree({ "x.zzra" })
    project.forget()
    with_module("nvim-treesitter", fake_ts({}, { "zzra" }), function()
      local asked = {}
      H.with_patched(vim.fn, "confirm", function(text)
        asked[#asked + 1] = text
        return 2
      end, function()
        project.run(root, "install", { registered = false })
        ok(
          vim.wait(5000, function()
            return #asked >= 1
          end, 5),
          "run: install scans, builds the report and asks"
        )
        ok(asked[1]:find("zzra", 1, true), "run: the question names the missing parser")
      end)
    end)
    project.forget()
    vim.fn.delete(root, "rf")
  end

  -- ------------------------------------------------------------------ routes
  do
    local found
    for _, route in ipairs(require("lib.nvim.deps").routes()) do
      if route.path[1] == "deps" and route.path[2] == "project" then
        found = route
      end
    end
    ok(found ~= nil, "routes: `:Lib deps project` is registered")
    eq(found.args[1].optional, true, "routes: the action is optional")
    eq(table.concat(found.args[1].enum, ","), "refresh,install", "routes: refresh|install")
    ok(require("lib.nvim.deps").project == project, "deps.project is reachable from lib.nvim.deps")
  end
end
