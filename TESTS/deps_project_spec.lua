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
  local walk = require("lib.nvim.deps.project.walk")

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

  ---Run `fn(n)` with the real walk counted: `n.walks` starts, `n.opts[i]`
  ---the options of start i.
  ---@param fn fun(n: { walks: integer, opts: table[] })
  local function counting_walks(fn)
    local n = { walks = 0, opts = {} }
    local real = walk.run
    H.with_patched(walk, "run", function(root, opts, on_done)
      n.walks = n.walks + 1
      n.opts[#n.opts + 1] = opts
      return real(root, opts, on_done)
    end, function()
      fn(n)
    end)
  end

  ---Run `fn(starts)` with a stand-in walk that never touches the disk: every
  ---start is recorded (`root`, `opts`, `on_done`, `cancelled` = how often its
  ---cancel function ran) and answered only when the test calls `on_done`.
  ---@param fn fun(starts: table[])
  local function fake_walks(fn)
    local starts = {}
    H.with_patched(walk, "run", function(root, opts, on_done)
      local start = { root = root, opts = opts, on_done = on_done, cancelled = 0 }
      starts[#starts + 1] = start
      return function()
        start.cancelled = start.cancelled + 1
      end
    end, function()
      fn(starts)
    end)
  end

  ---A `Lib.Deps.Project.WalkResult` with `over` applied.
  ---@param over? table
  ---@return Lib.Deps.Project.WalkResult
  local function walk_result(over)
    return vim.tbl_extend("force", { keys = {}, total = 0, root_unreadable = false }, over or {})
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
    counting_walks(function(n)
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
      eq(n.walks, 1, "scan: two callers of one root share one walk")
      eq(first, second, "scan: and receive the same result")
      eq(n.opts[1].max_files, walk.DEFAULTS.max_files, "scan: default file limit")
      eq(n.opts[1].max_depth, walk.DEFAULTS.max_depth, "scan: default depth limit")
      eq(n.opts[1].max_ms, walk.DEFAULTS.max_ms, "scan: default time limit")
    end)

    -- Cache policy: an unreadable SUBdirectory is cached, an unreadable root
    -- or a walk that died is not.
    project.forget()
    fake_walks(function(starts)
      local partial
      project.scan(root, nil, function(s)
        partial = s
      end)
      starts[1].on_done(walk_result({ total = 1, errors = { root .. "/locked: EACCES" } }))
      eq(partial.errors[1], root .. "/locked: EACCES", "scan: errors are delivered")
      local cached
      project.scan(root, nil, function(s)
        cached = s
      end)
      eq(#starts, 1, "scan: a walk with an unreadable subdirectory is cached")
      ok(
        vim.wait(2000, function()
          return cached ~= nil
        end, 5),
        "scan: the cache answers"
      )
      eq(cached, partial, "scan: with that scan")

      project.forget()
      project.scan(root, nil, function() end)
      starts[2].on_done(walk_result({ errors = { root .. ": ENOENT" }, root_unreadable = true }))
      project.scan(root, nil, function() end)
      eq(#starts, 3, "scan: a walk whose root could not be read is not cached")
      starts[3].on_done(walk_result({ failed = "boom" }))
      project.scan(root, nil, function() end)
      eq(#starts, 4, "scan: a failed walk is not cached")
      starts[4].on_done(walk_result())
    end)

    -- Cancel: only the waiter that cancelled goes; the walk stops with the last one.
    project.forget()
    fake_walks(function(starts)
      local first_fired, second = false, nil
      local cancel_first = project.scan(root, nil, function()
        first_fired = true
      end)
      project.scan(root, nil, function(s)
        second = s
      end)
      eq(#starts, 1, "cancel: two waiters share one walk")
      cancel_first()
      eq(starts[1].cancelled, 0, "cancel: the walk goes on while another caller waits")
      starts[1].on_done(walk_result({ total = 7 }))
      eq(first_fired, false, "cancel: a cancelled wait is never called back")
      eq(second and second.total, 7, "cancel: the caller still waiting gets the scan")

      project.forget()
      local fired = false
      local cancel = project.scan(root, nil, function()
        fired = true
      end)
      cancel()
      eq(starts[2].cancelled, 1, "cancel: the last waiter leaving stops the walk")
      project.scan(root, nil, function() end)
      eq(#starts, 3, "cancel: the next caller does not join the stopped walk")
      starts[3].on_done(walk_result())
      eq(fired, false, "cancel: the cancelled caller is not answered by the next walk")
    end)

    -- A walk that throws (here: the caller's ignore function) still answers,
    -- and leaves nothing behind that later scans of the root would hang on.
    project.forget()
    local died = await(function(done)
      project.scan(root, {
        ignore = function()
          error("boom from ignore")
        end,
      }, done)
    end)
    ok(
      died.failed and died.failed:find("boom from ignore", 1, true),
      "scan: a throwing walk -> failed"
    )
    local after = await(function(done)
      project.scan(root, nil, done)
    end)
    eq(after.failed, nil, "scan: the next scan of that root walks again")
    eq(after.keys["*.lua"].count, 4, "scan: and counts normally")

    -- Limits.
    project.forget()
    local capped = await(function(done)
      project.scan(root, { max_files = 2 }, done)
    end)
    eq(capped.total, 2, "limits: max_files stops the count")
    eq(capped.truncated, "max_files", "limits: and says so")
    local shallow = await(function(done)
      project.scan(root, { refresh = true, max_depth = 0 }, done)
    end)
    eq(shallow.keys["*.zzra"], nil, "limits: max_depth = 0 does not enter sub/")
    eq(shallow.keys["*.lua"].count, 4, "limits: but counts the root's own files")
    eq(shallow.truncated, "max_depth", "limits: and says that it pruned")
    local timed = await(function(done)
      project.scan(root, { refresh = true, max_ms = 0 }, done)
    end)
    eq(timed.truncated, "max_ms", "limits: max_ms stops the walk")
    eq(timed.total, 0, "limits: max_ms = 0 counts nothing")

    -- A truncated scan answers requests with the same limits, not larger ones.
    project.forget()
    counting_walks(function(n)
      await(function(done)
        project.scan(root, { max_files = 2 }, done)
      end)
      await(function(done)
        project.scan(root, { max_files = 2 }, done)
      end)
      eq(n.walks, 1, "limits: a truncated scan is cached for the same limits")
      local full = await(function(done)
        project.scan(root, nil, done)
      end)
      eq(n.walks, 2, "limits: a request with larger limits walks again")
      eq(full.truncated, nil, "limits: and gets the whole tree")
    end)

    -- forget(root) drops that root only.
    project.forget()
    local other = tree({ "o.lua" })
    counting_walks(function(n)
      for _, r in ipairs({ root, other }) do
        await(function(done)
          project.scan(r, nil, done)
        end)
      end
      project.forget(root)
      await(function(done)
        project.scan(root, nil, done)
      end)
      eq(n.walks, 3, "forget(root): that root is walked again")
      await(function(done)
        project.scan(other, nil, done)
      end)
      eq(n.walks, 3, "forget(root): another root stays cached")
    end)
    vim.fn.delete(other, "rf")

    vim.fn.delete(root, "rf")
    project.forget()
  end

  -- ------------------------------------------------------------ the walk
  do
    local root = tree({ "a.lua", "sub/b.lua" })
    local uv = vim.uv or vim.loop
    local real_scandir = uv.fs_scandir
    H.with_patched(uv, "fs_scandir", function(dir, cb)
      if dir:sub(-4) == "/sub" then
        vim.schedule(function()
          cb("EACCES: permission denied", nil)
        end)
        return
      end
      return real_scandir(dir, cb)
    end, function()
      local r = await(function(done)
        walk.run(root, nil, done)
      end)
      eq(r.errors[1], root .. "/sub: EACCES: permission denied", "walk: an unreadable subdirectory")
      eq(r.root_unreadable, false, "walk: is not an unreadable root")
      eq(r.total, 1, "walk: the readable rest is counted")
    end)
    local gone = await(function(done)
      walk.run(root .. "/does-not-exist", nil, done)
    end)
    eq(gone.root_unreadable, true, "walk: a root that cannot be opened is flagged")
    eq(gone.total, 0, "walk: and counts nothing")
    vim.fn.delete(root, "rf")
  end

  -- -------------------------------------------------------- default_ignore
  do
    local ignore = project.default_ignore()
    eq(ignore("/r/.github", true), false, "default_ignore: .github is project content")
    eq(ignore("/r/node_modules", true), true, "default_ignore: node_modules is pruned")
    eq(ignore("/r/bin", true), true, "default_ignore: bin/ counts as build output (documented)")
    eq(ignore("/r/main.lua", false), false, "default_ignore: sources are kept")
    if package.config:sub(1, 1) == "\\" then
      eq(ignore("C:/r/Thumbs.db", false), true, "default_ignore: case-insensitive on Windows")
      eq(ignore("C:/r/Node_Modules", true), true, "default_ignore: also for directories")
    else
      eq(ignore("/r/Node_Modules", true), false, "default_ignore: case-sensitive elsewhere")
    end

    local root = tree({ ".github/workflows/ci.yml", "x.lua" })
    project.forget()
    local scan = await(function(done)
      project.scan(root, nil, done)
    end)
    eq(scan.keys["*.yml"] and scan.keys["*.yml"].count, 1, "scan: .github workflows are counted")
    project.forget()
    vim.fn.delete(root, "rf")
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
      ok(
        text:find("Nothing missing for the files in this root.", 1, true),
        "lines: says so when nothing is missing"
      )
    end)
  end

  -- ------------------------------------- partial scans, unusable entries
  do
    local paths = { "/proj/a.zzra" }
    with_module("nvim-treesitter", fake_ts({ "zzra" }, { "zzra" }), function()
      ---@param over table fields set on the scan
      ---@return string text, Lib.Deps.Project.Report report
      local function text_of(over)
        local scan = vim.tbl_extend("force", scan_of(paths), over)
        local report = project.report(scan, { registered = false })
        return table.concat(project.lines(report), "\n"), report
      end
      local whole = "Nothing missing for the files in this root."
      local partial = "Nothing missing for the files that were counted"

      local text, report = text_of({ errors = { "/proj/locked: EACCES" } })
      eq(
        report.errors and report.errors[1],
        "/proj/locked: EACCES",
        "report: carries the scan's errors"
      )
      ok(text:find("1 directory could not be read", 1, true), "lines: names unreadable directories")
      ok(text:find(partial, 1, true), "lines: errors -> nothing missing among what was counted")
      ok(not text:find(whole, 1, true), "lines: errors -> not 'nothing missing in this root'")

      text, report = text_of({
        truncated = "max_files",
        limits = { max_files = 2, max_depth = 32, max_ms = 30000 },
      })
      eq(report.truncated, "max_files", "report: carries truncated")
      ok(text:find("it stopped after 2 files", 1, true), "lines: names the file limit")
      ok(text:find(partial, 1, true), "lines: truncated -> partial")
      ok(not text:find(whole, 1, true), "lines: truncated -> not 'nothing missing'")

      text, report = text_of({ failed = "boom" })
      eq(report.failed, "boom", "report: carries failed")
      ok(text:find("The walk failed: boom", 1, true), "lines: names the failure")
      ok(not text:find(whole, 1, true), "lines: failed -> not 'nothing missing'")

      -- Mason entries that could not be checked, and unusable table entries.
      with_module("mason-registry", {
        get_package = function(name)
          error("Cannot find package " .. name)
        end,
      }, function()
        local r = project.report(scan_of(paths), {
          registered = false,
          tools = { zzra = { { mason = "zz-typo" }, { why = "neither bin nor mason" } } },
        })
        local t = table.concat(project.lines(r), "\n")
        ok(t:find("## Could not be checked", 1, true), "lines: 'Could not be checked' section")
        ok(t:find("zz-typo (not in the Mason registry", 1, true), "lines: names the package")
        ok(t:find("## Tools table problems", 1, true), "lines: 'Tools table problems' section")
        ok(t:find("zzra: entry has neither `bin` nor `mason`", 1, true), "lines: names the problem")
        ok(
          t:find("Nothing missing among what could be checked", 1, true),
          "lines: unchecked entries -> not a plain 'nothing missing'"
        )
        ok(not t:find(whole, 1, true), "lines: unchecked entries -> not 'nothing missing'")
      end)
    end)

    -- summary: a "Never" parser is not announced; a root without a tail still has a name.
    with_module("nvim-treesitter", fake_ts({}, { "zzra", "zzgo" }), function()
      H.with_patched(policy, "declined", function()
        return { "zzgo" }
      end, function()
        local only_never = project.report(scan_of({ "/proj/a.zzgo" }), { registered = false })
        eq(project.summary(only_never), nil, "summary: a declined parser alone is not announced")
        local both = project.report(scan_of({ "/proj/a.zzgo", "/proj/a.zzra" }), {
          registered = false,
        })
        local summary = project.summary(both)
        ok(summary:find("parsers: zzra", 1, true), "summary: the installable one is named")
        ok(not summary:find("zzgo", 1, true), "summary: the declined one is not")
      end)
    end)
    local rooted = project.summary({
      root = "/",
      missing_parsers = { { lang = "zzra", state = "available" } },
      missing_tools = {},
    })
    eq(
      rooted:find("/ — missing", 1, true),
      1,
      "summary: a root without a tail is named by its path"
    )
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

        -- Only a Mason package missing (lua's parser is installed): not empty.
        local mason_only = project.install_plan(project.report(scan_of({ "/proj/c.lua" }), {
          registered = false,
          tools = { lua = { { mason = "stylua" } } },
        }))
        eq(#mason_only.parsers, 0, "install_plan: no parser in the Mason-only case")
        eq(mason_only.empty, false, "install_plan: a missing Mason package alone is not empty")
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
                H.with_patched(require("lib.nvim.ui.dialog"), "yesno", function(text, _, cb)
                  asked[#asked + 1] = text
                  cb(answer == 1)
                end, body)
              end)
            end)
          end)
        end

        -- Cancel: asked, nothing started.
        recorders(2, function()
          local ended, started = false, "unset"
          local returned = project.install(report, {
            manager = pm.get("brew"),
            on_done = function(result)
              ended, started = true, result
            end,
          })
          eq(returned, nil, "install: the question is open when the call returns -> nil")
          eq(ended, true, "install: on_done says how it ended")
          eq(started, nil, "install: cancelled -> nil")
        end)
        eq(#asked, 1, "install: asks exactly once before doing anything")
        ok(asked[1]:find("zzra", 1, true), "install: the question names the parser")
        eq(#parsers + #masons + #runs, 0, "install: cancelled starts nothing")

        -- Yes: all three ways, with the terminal one unconfirmed a second time.
        asked = {}
        recorders(1, function()
          local started
          project.install(report, {
            manager = pm.get("brew"),
            on_done = function(result)
              started = result
            end,
          })
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
      local refreshed
      mason.refresh(function(success)
        refreshed = success
      end)
      eq(refreshed, false, "mason.refresh: without Mason it answers false, right away")
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

  -- ----------------------------------------------------------- report_async
  do
    -- A Mason that never fetched its registry: get_package raises for every
    -- name until refresh() ran (real Mason behaves like this on a fresh machine).
    local fetched, refreshes = false, 0
    local fresh_registry = {
      refresh = function(cb)
        refreshes = refreshes + 1
        fetched = true
        cb(true, {})
      end,
      get_package = function(name)
        if not fetched or name ~= "rust-analyzer" then
          error("Cannot find package " .. name)
        end
        return {
          is_installed = function()
            return false
          end,
        }
      end,
    }
    local function opts_for(name)
      return { registered = false, tools = { zzra = { { mason = name } } } }
    end
    with_module("nvim-treesitter", fake_ts({ "zzra" }, { "zzra" }), function()
      with_module("mason-registry", fresh_registry, function()
        local scan = scan_of({ "/proj/a.zzra" })
        eq(
          project.report(scan, opts_for("rust-analyzer")).tools[1].state,
          "unavailable",
          "fresh Mason: before a fetch every package is unavailable"
        )
        local report = await(function(done)
          project.report_async(scan, opts_for("rust-analyzer"), done)
        end)
        eq(refreshes, 1, "report_async: an unavailable Mason entry refreshes the registry")
        eq(report.tools[1].state, "missing", "report_async: after which the package is missing")
        eq(
          project.install_plan(report).mason[1],
          "rust-analyzer",
          "report_async: and offered for install"
        )

        await(function(done)
          project.report_async(scan, opts_for("rust-analyzer"), done)
        end)
        eq(refreshes, 1, "report_async: nothing unavailable -> no refresh")

        local typo = await(function(done)
          project.report_async(scan, opts_for("zz-typo"), done)
        end)
        eq(refreshes, 2, "report_async: one refresh per report, not a loop")
        eq(typo.tools[1].state, "unavailable", "report_async: a typo stays unavailable")
      end)

      -- The trigger on that fresh machine announces the package.
      fetched = false
      local auto_root = tree({ "x.zzra" })
      project.forget()
      project.reset_announced()
      with_module("mason-registry", fresh_registry, function()
        local infos = {}
        H.with_patched(require("lib.nvim.notify"), "create", function()
          return {
            info = function(msg)
              infos[#infos + 1] = msg
            end,
            warn = function() end,
            error = function() end,
            debug = function() end,
          }
        end, function()
          local old_cwd = vim.fn.getcwd()
          vim.cmd("cd " .. vim.fn.fnameescape(auto_root))
          local ok_run, err = pcall(function()
            project.setup({ auto = true, tools = opts_for("rust-analyzer").tools })
            ok(
              vim.wait(5000, function()
                return #infos >= 1
              end, 5),
              "trigger: a fresh Mason still gets announced"
            )
            ok(infos[1]:find("tools: rust-analyzer", 1, true), "trigger: naming the package")
          end)
          project.setup({})
          vim.cmd("cd " .. vim.fn.fnameescape(old_cwd))
          if not ok_run then
            error(err, 0)
          end
        end)
      end)
      project.reset_announced()
      project.forget()
      vim.fn.delete(auto_root, "rf")

      -- :Lib deps project install on that fresh machine offers the package.
      fetched = false
      local root = tree({ "x.zzra" })
      project.forget()
      with_module("mason-registry", fresh_registry, function()
        local asked = {}
        H.with_patched(require("lib.nvim.ui.dialog"), "yesno", function(text)
          asked[#asked + 1] = text
        end, function()
          project.run(root, "install", opts_for("rust-analyzer"))
          ok(
            vim.wait(5000, function()
              return #asked >= 1
            end, 5),
            "run: a fresh Mason still gets asked about"
          )
          ok(asked[1]:find("rust-analyzer", 1, true), "run: the question names the Mason package")
        end)
      end)
      project.forget()
      vim.fn.delete(root, "rf")
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

  -- ----------------------------------------------- trigger: bounds and roots
  do
    local is_windows = package.config:sub(1, 1) == "\\"
    local uv = vim.uv or vim.loop
    -- Real paths: the directory a DirChanged event names is resolved (macOS:
    -- /var is /private/var), so the spec compares against resolved ones.
    local function real(p)
      return vim.fs.normalize(uv.fs_realpath(p) or p)
    end
    local a, b = real(tree({ "x.zzra" })), real(tree({ "y.zzra" }))
    local old_cwd = vim.fn.getcwd()
    local scans = {}
    local function cd(dir)
      vim.cmd("cd " .. vim.fn.fnameescape(dir))
    end

    eq(project.is_broad_root("/"), true, "is_broad_root: the filesystem root")
    eq(project.is_broad_root("C:/"), true, "is_broad_root: a drive root")
    eq(project.is_broad_root("C:"), true, "is_broad_root: a bare drive")
    eq(project.is_broad_root("//server/share"), true, "is_broad_root: a UNC share root")
    eq(project.is_broad_root(uv.os_homedir()), true, "is_broad_root: the home directory")
    eq(project.is_broad_root(a), false, "is_broad_root: a project directory is not")

    -- A home directory reached through a link is still the home directory.
    local link = vim.fs.normalize(vim.fn.tempname() .. "_homelink")
    if uv.fs_symlink(a, link, { dir = true, junction = true }) then
      local ok_link, link_err = pcall(function()
        H.with_patched(uv, "os_homedir", function()
          return link
        end, function()
          eq(project.is_broad_root(a), true, "is_broad_root: home behind a link, compared resolved")
        end)
      end)
      uv.fs_unlink(link)
      pcall(uv.fs_rmdir, link)
      if not ok_link then
        error(link_err, 0)
      end
    else
      H.skipped("is_broad_root through a link", "this host cannot create a directory link")
    end

    local ok_run, err = pcall(function()
      H.with_patched(project, "scan", function(root, opts, on_done)
        local s = { root = vim.fs.normalize(root), opts = opts, on_done = on_done, cancelled = 0 }
        scans[#scans + 1] = s
        return function()
          s.cancelled = s.cancelled + 1
        end
      end, function()
        cd(a)
        project.setup({ auto = true })
        eq(#scans, 1, "trigger: the current directory is scanned at setup")
        eq(scans[1].root, a, "trigger: that directory")
        eq(scans[1].opts.max_files, project.TRIGGER_LIMITS.max_files, "trigger: file limit")
        eq(scans[1].opts.max_depth, project.TRIGGER_LIMITS.max_depth, "trigger: depth limit")
        eq(scans[1].opts.max_ms, project.TRIGGER_LIMITS.max_ms, "trigger: time limit")

        -- getcwd() answers the OLD directory: only v:event.cwd names the new one.
        H.with_patched(vim.fn, "getcwd", function()
          return a
        end, function()
          cd(b)
        end)
        eq(#scans, 2, "trigger: a :cd starts a scan")
        eq(scans[2].root, b, "trigger: of the directory the DirChanged event names")
        eq(scans[1].cancelled, 1, "trigger: the next :cd cancels the scan still running")
        eq(scans[2].cancelled, 0, "trigger: but not its own")

        project.setup({ auto = true, max_files = 5, max_depth = 2, max_ms = 100 })
        eq(scans[2].cancelled, 1, "trigger: setup() again cancels the pending scan")
        eq(scans[3].opts.max_files, 5, "trigger: setup's max_files")
        eq(scans[3].opts.max_depth, 2, "trigger: setup's max_depth")
        eq(scans[3].opts.max_ms, 100, "trigger: setup's max_ms")

        H.with_patched(uv, "os_homedir", function()
          return a
        end, function()
          cd(a)
        end)
        eq(#scans, 3, "trigger: the home directory is not scanned")
        eq(scans[3].cancelled, 1, "trigger: leaving for it still cancels the running scan")

        cd(is_windows and a:sub(1, 3) or "/")
        eq(#scans, 3, "trigger: a filesystem or drive root is not scanned")

        cd(b)
        eq(#scans, 4, "trigger: back in a project directory it scans again")
        project.setup({})
        eq(scans[4].cancelled, 1, "trigger: turning it off cancels the pending scan")
      end)
    end)
    project.setup({})
    cd(old_cwd)
    vim.fn.delete(a, "rf")
    vim.fn.delete(b, "rf")
    if not ok_run then
      error(err, 0)
    end
  end

  -- -------------------------------------------------------------------- run
  do
    local root = tree({ "x.zzra" })

    -- The action decides whether the cache may answer.
    local seen = {}
    H.with_patched(project, "scan", function(_, opts)
      seen[#seen + 1] = opts
      return function() end
    end, function()
      project.run(root, "refresh")
      project.run(root)
    end)
    eq(seen[1].refresh, true, "run: refresh walks again")
    eq(seen[2].refresh, false, "run: without an action the cache may answer")

    -- Without an action: the report view, whose `I` installs.
    project.forget()
    with_module("nvim-treesitter", fake_ts({}, { "zzra" }), function()
      local before = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        before[win] = true
      end
      project.run(root, nil, { registered = false })
      local view
      ok(
        vim.wait(5000, function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if not before[win] then
              view = win
              return true
            end
          end
          return false
        end, 5),
        "run: without an action a view opens"
      )
      local buf = vim.api.nvim_win_get_buf(view)
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      ok(text:find("# Project scan", 1, true), "run: the view shows the report")
      ok(text:find("- zzra  (zzra, 1 file)", 1, true), "run: with the missing parser")
      local install_map
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == "I" then
          install_map = map
        end
      end
      ok(install_map and install_map.callback, "run: the view maps I")
      local asked = {}
      H.with_patched(require("lib.nvim.ui.dialog"), "yesno", function(question)
        asked[#asked + 1] = question
      end, function()
        install_map.callback()
      end)
      eq(#asked, 1, "run: I asks to install")
      ok(asked[1]:find("zzra", 1, true), "run: about the report's parser")
      pcall(vim.api.nvim_win_close, view, true)
    end)
    project.forget()
    vim.fn.delete(root, "rf")
  end

  do
    local root = tree({ "x.zzra" })
    project.forget()
    with_module("nvim-treesitter", fake_ts({}, { "zzra" }), function()
      local asked = {}
      H.with_patched(require("lib.nvim.ui.dialog"), "yesno", function(text)
        asked[#asked + 1] = text
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

  -- -------------------------------------------------------------- help tag
  do
    -- This checkout's help file, not whichever copy is first on runtimepath.
    local spec_dir = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))
    local lines = vim.fn.readfile(vim.fs.dirname(spec_dir) .. "/doc/lib.nvim-deps.txt")
    local entry
    for i, line in ipairs(lines) do
      if line:find("*:Lib-deps-project*", 1, true) then
        for j = i + 1, #lines do
          if lines[j] ~= "" then
            entry = lines[j]
            break
          end
        end
      end
    end
    ok(
      entry and entry:find("^:Lib deps project"),
      "help: *:Lib-deps-project* sits right above `:Lib deps project`"
    )
  end
end
