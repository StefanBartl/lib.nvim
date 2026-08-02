-- docs/TESTS/telemetry_spec.lua — lib.nvim.telemetry
--
-- Covers the properties the design actually rests on: zero-cost-when-stopped
-- (identity restore), scoping, the shared wrap layer (no double counting, no
-- restore-ordering trap), fingerprinting, merge-on-write persistence, day
-- windows, retention pruning and the lifecycle reminder.

return function(H)
  local telemetry = require("lib.nvim.telemetry")
  local store = require("lib.nvim.telemetry.store")
  local fingerprint = require("lib.nvim.telemetry.fingerprint")
  local reminder = require("lib.nvim.telemetry.reminder")
  local toggle = require("lib.nvim.telemetry.toggle")

  local seq = 0
  local function ns(name)
    seq = seq + 1
    return ("spec.%s.%d"):format(name, seq)
  end

  local tmpdir = vim.fn.tempname() .. "-telemetry"
  vim.fn.mkdir(tmpdir, "p")

  -- -------------------------------------------------------------------------
  -- namespace sanitization (cache.disk does none of its own)
  -- -------------------------------------------------------------------------
  H.eq(store.sanitize("lib.nvim"), "lib.nvim", "plain namespace untouched")
  H.eq(store.sanitize("../../evil"), "_.._evil", "path separators neutralized, leading dots dropped")
  H.eq(store.sanitize("a/b"), "a_b", "slash neutralized")
  H.eq(store.sanitize("..."), "unnamed", "dots-only namespace does not escape")
  H.eq(store.cache_key("x"):sub(1, 10), "telemetry/", "namespaced under telemetry/")

  -- -------------------------------------------------------------------------
  -- counting, and exact restore on stop
  -- -------------------------------------------------------------------------
  do
    local mod = {
      add = function(a, b)
        return a + b
      end,
      sub = function(a, b)
        return a - b
      end,
    }
    local original_add = mod.add

    local t = telemetry.new({ namespace = ns("count"), persist = false })
    H.eq(t.wrap(mod, "m"), 2, "both functions registered")
    H.eq(mod.add, original_add, "wrap() alone installs nothing")

    t.start()
    H.ok(mod.add ~= original_add, "start() installs the wrapper")
    H.eq(mod.add(2, 3), 5, "wrapper is transparent")
    mod.add(1, 1)
    mod.sub(9, 4)

    local rep = t.report()
    H.eq(rep.total_calls, 3, "three calls counted")
    H.eq(rep.entries[1].key, "m.add", "busiest first")
    H.eq(rep.entries[1].calls, 2, "add counted twice")

    t.stop()
    H.eq(mod.add, original_add, "stop() restores the original object exactly")
    H.eq(t.report().total_calls, 3, "stop() keeps collected data")
    H.eq(t.is_running(), false, "not running after stop")
    H.eq(t.stop(), false, "second stop is a no-op, not an error")
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- multiple return values and varargs survive the wrapper
  -- -------------------------------------------------------------------------
  do
    local mod = {
      multi = function()
        return 1, nil, 3
      end,
      count = function(...)
        return select("#", ...)
      end,
    }
    local t = telemetry.new({ namespace = ns("passthrough"), persist = false })
    t.wrap(mod)
    t.start({ time = true })

    local a, b, c = mod.multi()
    H.eq(a, 1, "first return")
    H.eq(b, nil, "nil hole preserved")
    H.eq(c, 3, "trailing return preserved")
    H.eq(mod.count(1, nil, nil), 3, "arity preserved through the wrapper")

    t.stop()
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- scoping: only / except / filter
  -- -------------------------------------------------------------------------
  do
    local mod = { a = function() end, b = function() end, _priv = function() end }

    local t1 = telemetry.new({ namespace = ns("only"), persist = false })
    H.eq(t1.wrap(mod, nil, { only = { "a" } }), 1, "only wraps one")
    H.eq(t1.wrapped_keys()[1], "a", "the listed one")

    local t2 = telemetry.new({ namespace = ns("except"), persist = false })
    H.eq(t2.wrap(mod, nil, { except = { "a", "b" } }), 1, "except skips two")

    local t3 = telemetry.new({ namespace = ns("filter"), persist = false })
    H.eq(
      t3.wrap(mod, nil, {
        filter = function(name)
          return not name:match("^_")
        end,
      }),
      2,
      "filter drops the private one"
    )
  end

  -- -------------------------------------------------------------------------
  -- wrap_fn: a function with no table to hang it off
  -- -------------------------------------------------------------------------
  do
    local t = telemetry.new({ namespace = ns("fn"), persist = false })
    local traced = t.wrap_fn(function(x)
      return x * 2
    end, "double")

    H.eq(traced(21), 42, "dispatcher is transparent before start")
    t.start()
    H.eq(traced(4), 8, "dispatcher is transparent while running")
    t.stop()
    H.eq(traced(1), 2, "dispatcher still works after stop")

    H.eq(t.report().entries[1].calls, 1, "only the call while running was counted")
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- module-id resolution: a plain wrap() resolves only if the caller vouches
  -- for the prefix explicitly -- the prefix is a label, not necessarily a
  -- real module path, and a guess here is exactly the failure mode the
  -- documentation.nvim join has to avoid (see wrap_loaded's own resolution
  -- test further down, where the module path is never guessed either).
  -- -------------------------------------------------------------------------
  do
    local mod = { f = function() end }

    local t1 = telemetry.new({ namespace = ns("wrap_unresolved"), persist = false })
    t1.wrap(mod, "servers")
    H.eq(next(t1.resolved_modules()), nil, "a bare wrap() prefix resolves nothing")
    t1.unwrap()

    local t2 = telemetry.new({ namespace = ns("wrap_resolved"), persist = false })
    t2.wrap(mod, "servers", { module_id = "lsp.servers" })
    H.eq(
      t2.resolved_modules()["servers.f"],
      "lsp.servers",
      "an explicit module_id is honored for a plain wrap()"
    )
    t2.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- shared wrap layer: two instances, one function
  -- -------------------------------------------------------------------------
  do
    local mod = {
      shared = function()
        return true
      end,
    }
    local original = mod.shared

    local outer = telemetry.new({ namespace = ns("outer"), persist = false })
    local inner = telemetry.new({ namespace = ns("inner"), persist = false })

    outer.wrap(mod, "o")
    outer.start()
    local after_outer = mod.shared

    inner.wrap(mod, "i")
    inner.start()
    H.eq(mod.shared, after_outer, "second instance reuses the one wrapper, no nesting")

    mod.shared()
    mod.shared()

    H.eq(outer.report().entries[1].calls, 2, "outer sees both calls")
    H.eq(inner.report().entries[1].calls, 2, "inner sees both calls, not four")

    -- The restore-ordering trap: inner detaching first must not leave the
    -- wrapper installed as if it were the original.
    inner.stop()
    H.ok(mod.shared ~= original, "still wrapped while one subscriber remains")
    outer.stop()
    H.eq(mod.shared, original, "last one out restores the true original")

    outer.unwrap()
    inner.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- wrap_loaded: the whole loaded subtree, module-level scoping, stable keys
  -- -------------------------------------------------------------------------
  do
    -- A fake plugin: a thin façade plus the submodules that hold the real
    -- functions -- the shape wrap_loaded exists for.
    package.loaded["fakeplug"] = { facade = function() end }
    package.loaded["fakeplug.core"] = { a = function() end, b = function() end }
    package.loaded["fakeplug.bindings.actions"] = { go = function(x) return x end }
    package.loaded["fakeplug.@types"] = { noise = function() end }
    package.loaded["fakeplugother"] = { must_not_match = function() end }

    local t = telemetry.new({ namespace = ns("loaded"), persist = false })
    local n, mods = t.wrap_loaded("fakeplug")
    H.eq(n, 5, "façade + every loaded submodule")
    H.eq(mods, 4, "four modules contributed")

    local keys = t.wrapped_keys()
    H.ok(vim.tbl_contains(keys, "facade"), "the prefix module itself keeps bare keys")
    H.ok(vim.tbl_contains(keys, "core.a"), "submodule keys drop the prefix")
    H.ok(
      vim.tbl_contains(keys, "bindings.actions.go"),
      "nested submodule keeps its full relative path"
    )
    H.eq(vim.tbl_contains(keys, "must_not_match"), false, "prefix match is on a dot boundary")
    t.unwrap()

    -- module_filter / module_except / module_only
    local t2 = telemetry.new({ namespace = ns("loaded_filter"), persist = false })
    local n2 = t2.wrap_loaded("fakeplug", {
      module_filter = function(name)
        return not name:match("@types")
      end,
    })
    H.eq(n2, 4, "module_filter drops the @types module")
    t2.unwrap()

    local t3 = telemetry.new({ namespace = ns("loaded_only"), persist = false })
    H.eq(
      t3.wrap_loaded("fakeplug", { module_only = { "fakeplug.bindings.actions" } }),
      1,
      "module_only narrows to one module"
    )
    H.eq(t3.wrapped_keys()[1], "bindings.actions.go", "and its key is still prefix-relative")
    t3.unwrap()

    local t4 = telemetry.new({ namespace = ns("loaded_except"), persist = false })
    H.eq(
      t4.wrap_loaded("fakeplug", { module_except = { "fakeplug.core", "fakeplug.@types" } }),
      2,
      "module_except removes whole modules"
    )
    t4.unwrap()

    -- per-function scoping still applies underneath the module scoping
    local t5 = telemetry.new({ namespace = ns("loaded_fn"), persist = false })
    H.eq(
      t5.wrap_loaded("fakeplug", { only = { "a", "go" } }),
      2,
      "only/except/filter still scope functions within each module"
    )
    t5.unwrap()

    -- counting + argument profiling by predicate over the structured key
    local t6 = telemetry.new({ namespace = ns("loaded_args"), persist = false })
    t6.wrap_loaded("fakeplug")
    t6.start({
      profile_args = function(key)
        return key:match("^bindings%.") ~= nil
      end,
    })
    package.loaded["fakeplug.bindings.actions"].go("/repo/x")
    package.loaded["fakeplug.bindings.actions"].go("/repo/x")
    package.loaded["fakeplug.core"].a()

    local by_key = {}
    for _, e in ipairs(t6.report().entries) do
      by_key[e.key] = e
    end
    H.eq(by_key["bindings.actions.go"].calls, 2, "predicate-selected function counted")
    H.eq(
      by_key["bindings.actions.go"].args[1].fingerprint,
      '("/repo/x")',
      "and its arguments were fingerprinted"
    )
    H.eq(by_key["core.a"].args, nil, "a key the predicate rejected has no argument profile")
    t6.stop()
    t6.unwrap()

    -- re-registering is a no-op, so calling wrap_loaded again to pick up
    -- newly-required modules cannot double-count
    local t7 = telemetry.new({ namespace = ns("loaded_again"), persist = false })
    local first = t7.wrap_loaded("fakeplug")
    H.eq(t7.wrap_loaded("fakeplug"), first, "second call re-registers the same targets")
    H.eq(#t7.wrapped_keys(), first, "target list did not grow")
    t7.start()
    package.loaded["fakeplug.core"].a()
    H.eq(t7.report().total_calls, 1, "one call is counted once, not twice")
    t7.stop()
    t7.unwrap()

    H.eq(t7.wrap_loaded(""), 0, "an empty prefix registers nothing")

    -- module-id resolution: every wrap_loaded() key is derived from a real
    -- `package.loaded` path, so every one of them resolves.
    local t8 = telemetry.new({ namespace = ns("loaded_modules"), persist = false })
    t8.wrap_loaded("fakeplug")
    local resolved = t8.resolved_modules()
    H.eq(resolved.facade, "fakeplug", "the prefix module itself resolves to the prefix path")
    H.eq(resolved["core.a"], "fakeplug.core", "a submodule key resolves to its real module path")
    H.eq(
      resolved["bindings.actions.go"],
      "fakeplug.bindings.actions",
      "a nested submodule key resolves too"
    )
    t8.unwrap()

    for _, name in ipairs({
      "fakeplug",
      "fakeplug.core",
      "fakeplug.bindings.actions",
      "fakeplug.@types",
      "fakeplugother",
    }) do
      package.loaded[name] = nil
    end
  end

  -- -------------------------------------------------------------------------
  -- argument fingerprinting
  -- -------------------------------------------------------------------------
  H.eq(fingerprint.of(0), "()", "no arguments")
  H.eq(fingerprint.value(true), "true", "boolean by value")
  H.eq(fingerprint.value({ 1, 2, 3 }), "<table:#3>", "table by shape, not contents")
  H.eq(fingerprint.value({}), "<table:empty>", "empty table")
  H.eq(fingerprint.value(print), "<function>", "function by type")
  H.ok(
    #fingerprint.value(("x"):rep(500)) < 60,
    "long strings truncated rather than stored whole"
  )

  do
    local mod = {
      find = function(path)
        return path
      end,
    }
    local t = telemetry.new({ namespace = ns("args"), persist = false })
    t.wrap(mod, "fs")
    t.start({ profile_args = { "fs.find" } })

    for _ = 1, 19 do
      mod.find("/repo/lib.nvim")
    end
    mod.find("/repo/other")

    local entry = t.report().entries[1]
    H.eq(entry.calls, 20, "all calls counted")
    H.eq(entry.args[1].fingerprint, '("/repo/lib.nvim")', "dominant fingerprint first")
    H.eq(entry.args[1].count, 19, "dominant count")
    H.ok(entry.hint ~= nil, "dominant argument produces the memoization hint")
    H.ok(entry.hint:find("memo", 1, true) ~= nil, "hint points at lib.lua.memo")

    t.stop()
    t.unwrap()
  end

  -- bounded cardinality: distinct fingerprints do not grow without limit
  do
    local mod = {
      f = function(x)
        return x
      end,
    }
    local t = telemetry.new({ namespace = ns("bounded"), persist = false, max_arg_values = 4 })
    t.wrap(mod)
    t.start({ profile_args = true })
    for i = 1, 50 do
      mod.f(i)
    end
    t.stop()

    local entry = t.report().entries[1]
    H.eq(#entry.args, 4, "kept exactly max_arg_values distinct fingerprints")
    H.eq(entry.other, 46, "the rest landed in the other bucket")
    H.eq(entry.distinct, 50, "distinct count still reported honestly")
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- timing and error counting
  -- -------------------------------------------------------------------------
  do
    local mod = {
      slow = function()
        local x = 0
        for i = 1, 20000 do
          x = x + i
        end
        return x
      end,
      boom = function()
        error("nope")
      end,
    }
    local t = telemetry.new({ namespace = ns("timing"), persist = false })
    t.wrap(mod)
    t.start({ time = { "slow" }, errors = { "boom" } })

    mod.slow()
    mod.slow()
    local ok = pcall(mod.boom)
    H.eq(ok, false, "errors still propagate through the wrapper")

    local rep = t.report()
    local by_key = {}
    for _, e in ipairs(rep.entries) do
      by_key[e.key] = e
    end
    H.ok(by_key.slow.mean_ms ~= nil, "timing recorded")
    H.ok(by_key.slow.mean_ms >= 0, "mean is a number")
    H.eq(by_key.boom.errors, 1, "raised error counted")
    H.eq(rep.modes.timing, true, "report states it collected timing")
    H.eq(rep.modes.errors, true, "report states it collected errors")

    t.stop()
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- recursion: every entry by default, outermost only on request
  -- -------------------------------------------------------------------------
  do
    local mod = {}
    mod.down = function(n)
      if n <= 0 then
        return 0
      end
      return mod.down(n - 1)
    end

    local t = telemetry.new({ namespace = ns("recursive"), persist = false })
    t.wrap(mod)
    t.start()
    mod.down(3)
    H.eq(t.report().entries[1].calls, 4, "every entry counted by default")
    t.stop()
    t.unwrap()

    local mod2 = {}
    mod2.down = function(n)
      if n <= 0 then
        return 0
      end
      return mod2.down(n - 1)
    end
    local t2 = telemetry.new({ namespace = ns("outermost"), persist = false })
    t2.wrap(mod2, nil, { outermost_only = true })
    t2.start()
    mod2.down(3)
    H.eq(t2.report().entries[1].calls, 1, "outermost_only collapses the chain")
    t2.stop()
    t2.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- coverage: the never-called set
  -- -------------------------------------------------------------------------
  do
    local mod = { used = function() end, unused = function() end }
    local t = telemetry.new({ namespace = ns("coverage"), persist = false })
    t.wrap(mod)
    t.start()
    mod.used()
    t.stop()

    local cov = t.coverage()
    H.eq(#cov.called, 1, "one called")
    H.eq(cov.called[1], "used", "the right one")
    H.eq(cov.uncalled[1], "unused", "dead surface surfaced")
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- persistence: merge-on-write, not last-write-wins
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("persist")
    local mod = { f = function() end }

    local t1 = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    t1.reset()
    t1.wrap(mod)
    t1.start()
    mod.f()
    mod.f()
    t1.stop() -- flushes
    t1.unwrap()

    local on_disk = store.load(namespace, { dir = tmpdir })
    H.eq(on_disk.functions.f.calls, 2, "counts reached the disk")

    -- A second process (same namespace, fresh instance) must add to that.
    -- The "already has a live instance" warning this prints is the point of
    -- question 5 in the concept doc, and is expected here.
    local t2 = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    H.eq(t2.report().total_calls, 2, "previous run's counts loaded back")
    t2.wrap(mod)
    t2.start()
    mod.f()
    t2.stop()
    t2.unwrap()

    H.eq(store.load(namespace, { dir = tmpdir }).functions.f.calls, 3, "merged, not overwritten")
    H.eq(store.load(namespace, { dir = tmpdir }).sessions, 2, "session counter advanced")

    t2.reset()
    H.eq(store.load(namespace, { dir = tmpdir }).functions.f, nil, "reset clears the disk copy")
  end

  -- -------------------------------------------------------------------------
  -- reset(): the module-id map is repopulated from the still-wrapped targets
  -- immediately, not left empty until something calls wrap() again -- reset()
  -- promises "wrapping is untouched", and the module map is a property of the
  -- wrapping, not of the counts it clears.
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("reset_modules")
    package.loaded["fakeplug_reset"] = { go = function() end }

    local t = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    t.wrap_loaded("fakeplug_reset")
    t.start()
    package.loaded["fakeplug_reset"].go()
    t.stop() -- flush #1: counts and module map both on disk

    t.reset() -- clears memory + disk; wrapping (targets) is untouched
    H.eq(
      t.resolved_modules().go,
      "fakeplug_reset",
      "resolved_modules() reflects current targets right after reset()"
    )

    t.flush()
    H.eq(
      store.load_readonly(namespace, { dir = tmpdir }).modules.go,
      "fakeplug_reset",
      "the module-id map is back on disk after the next flush, without re-wrapping"
    )
    H.eq(
      store.load_readonly(namespace, { dir = tmpdir }).functions.go,
      nil,
      "counts stayed cleared -- only the module map was carried forward"
    )

    t.unwrap()
    package.loaded["fakeplug_reset"] = nil
  end

  -- -------------------------------------------------------------------------
  -- telemetry.load() / store.load_readonly(): read a namespace off disk with
  -- no live instance, distinguishing "never persisted" (nil) from "persisted,
  -- zero calls" -- the distinction documentation.nvim's join depends on so an
  -- unanalyzed tree renders as "no data", not a graveyard.
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("readonly")

    H.eq(store.load_readonly(namespace, { dir = tmpdir }), nil, "nothing on disk yet")
    H.eq(telemetry.load(namespace, { dir = tmpdir }), nil, "module-level load() agrees")

    package.loaded["fakeplug_ro"] = { go = function() end }
    local t = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    t.wrap_loaded("fakeplug_ro")
    t.start()
    package.loaded["fakeplug_ro"].go()
    t.stop() -- flushes
    t.unwrap()
    package.loaded["fakeplug_ro"] = nil

    local disk_readonly = store.load_readonly(namespace, { dir = tmpdir })
    H.ok(disk_readonly ~= nil, "data now exists on disk")
    H.eq(disk_readonly.functions.go.calls, 1, "counts round-trip")
    H.eq(disk_readonly.modules.go, "fakeplug_ro", "the module-id map round-trips too")

    local loaded = telemetry.load(namespace, { dir = tmpdir })
    H.eq(loaded.functions.go.calls, 1, "telemetry.load() sees the same data, no instance required")
    H.eq(loaded.modules.go, "fakeplug_ro", "...including the module map")

    H.eq(telemetry.load(nil, { dir = tmpdir }), nil, "a non-string namespace is refused, not errored on")
    H.eq(telemetry.load("", { dir = tmpdir }), nil, "an empty namespace is refused too")
  end

  -- -------------------------------------------------------------------------
  -- day buckets: `since` windows and retention pruning
  -- -------------------------------------------------------------------------
  do
    H.eq(store.parse_since("7d"), 7, "7d")
    H.eq(store.parse_since("24h"), 1, "24h rounds to a day")
    H.eq(store.parse_since("2w"), 14, "2w")
    H.eq(store.parse_since(3), 3, "bare number")
    H.eq(store.parse_since(nil), nil, "nil means no window")

    local data = store.empty()
    data.days[store.today()] = { recent = 5 }
    data.days[os.date("%Y-%m-%d", os.time() - 40 * 86400)] = { old = 7 }

    local windowed, total = store.since(data, 7)
    H.eq(total, 5, "only the in-window day counts")
    H.eq(windowed.old, nil, "old day excluded")

    H.eq(store.prune(data, 30), 1, "one stale bucket dropped")
    H.eq(store.count_keys(data.days), 1, "today's bucket kept")
  end

  -- -------------------------------------------------------------------------
  -- lifecycle reminder: fires once, persists that it fired, escalates once
  -- -------------------------------------------------------------------------
  do
    local data = store.empty()
    data.functions.f = { calls = 60000 }

    H.eq(reminder.check("demo", data, false), nil, "remind_after = false opts out")

    local msg = reminder.check("demo", data, { days = 7, calls = 50000 })
    H.ok(msg ~= nil, "volume trigger fires")
    H.ok(msg:find(":LibTelemetry demo", 1, true) ~= nil, "names the read command")
    H.ok(msg:find(":LibTelemetry stop", 1, true) ~= nil, "names the stop command")
    H.eq(data.reminded.first, true, "fired state persisted into the cache entry")

    H.eq(reminder.check("demo", data, { days = 7, calls = 50000 }), nil, "does not repeat")

    data.started_at = os.time() - 40 * 86400
    local second = reminder.check("demo", data, { days = 7, calls = 50000 })
    H.ok(second ~= nil, "escalates once past 4x the duration")
    H.eq(reminder.check("demo", data, { days = 7, calls = 50000 }), nil, "then stops for good")
  end

  -- -------------------------------------------------------------------------
  -- module-level registry + strategy introspection hook
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("registry")
    local t = telemetry.new({ namespace = namespace, persist = false })
    H.eq(telemetry.get(namespace), t, "instance discoverable by namespace")
    H.ok(#telemetry.instances() > 0, "instances() enumerates")

    local control = require("lib.strategies.control")
    local lib = require("lib")
    local keys = control.keys(lib)
    H.ok(#keys > 20, "aggregate key set is enumerable despite the metatable")
    local has_trim = false
    for _, k in ipairs(keys) do
      if k == "trim" then
        has_trim = true
      end
    end
    H.ok(has_trim, "special-handler keys included, not just MODULE_MAP")
  end

  -- report rendering must not throw on an empty instance
  do
    local t = telemetry.new({ namespace = ns("render"), persist = false })
    local lines = t.lines()
    H.ok(#lines > 0, "lines() renders something for an empty instance")
    H.ok(lines[1]:find("stopped", 1, true) ~= nil, "header reports the stopped state")
  end

  -- -------------------------------------------------------------------------
  -- toggle.lua: persistent disable, isolated from the real stdpath("cache")
  -- via an explicit dir (every function takes one for exactly this reason).
  -- -------------------------------------------------------------------------
  do
    local topts = { dir = tmpdir }
    local n1, n2 = ns("toggle_a"), ns("toggle_b")

    H.eq(toggle.is_disabled(n1, topts), false, "nothing disabled yet")
    toggle.disable(n1, topts)
    H.eq(toggle.is_disabled(n1, topts), true, "disable persists immediately")
    H.eq(toggle.is_disabled(n2, topts), false, "a different namespace is untouched")

    toggle.disable(n2, topts)
    local listed = toggle.disabled_list(topts)
    table.sort(listed)
    H.eq(#listed, 2, "disabled_list sees both")

    toggle.enable(n1, topts)
    H.eq(toggle.is_disabled(n1, topts), false, "enable clears it")
    H.eq(toggle.is_disabled(n2, topts), true, "enabling one leaves the other disabled")

    toggle.enable(n1, topts) -- enabling an already-enabled namespace: no-op, no error
    toggle.enable(n2, topts)
    H.eq(#toggle.disabled_list(topts), 0, "both cleared")
  end

  -- -------------------------------------------------------------------------
  -- disable/enable integration: inst.start() honors a persisted disable, and
  -- takes effect on a LIVE instance without the caller re-calling start().
  -- Isolated via dir=tmpdir (threaded into the same toggle checks above).
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("toggle_integration")
    local mod = { f = function() end }

    -- Disabling before the instance exists: the common case (`:LibTelemetry
    -- disable <ns>` for a plugin that has not loaded yet this session).
    telemetry.disable(namespace) -- module-level API has no dir param; see below

    -- Since the module-level disable() above has no way to know this
    -- instance will use `dir=tmpdir` (it doesn't exist yet), it persisted to
    -- the default cache — the documented edge case. Exercise the realistic
    -- path instead: disable AFTER the instance exists, which is what
    -- `:LibTelemetry disable <ns>` actually does for an already-loaded
    -- plugin, and is the path that matters for "persistently toggle a
    -- running plugin".
    telemetry.enable(namespace) -- undo the pre-emptive (default-dir) disable above

    local t = telemetry.new({ namespace = namespace, persist = false, dir = tmpdir })
    t.wrap(mod)
    H.eq(t.start(), true, "starts normally before any disable")
    mod.f()

    telemetry.disable(namespace)
    H.eq(t.is_running(), false, "telemetry.disable() stops a live, running instance immediately")
    H.eq(toggle.is_disabled(namespace, t._cache_opts), true, "persisted under the instance's own dir")

    H.eq(t.start(), false, "start() is a no-op while disabled")
    H.eq(t.is_running(), false, "...and does not report itself as running")

    telemetry.enable(namespace)
    H.eq(t.is_running(), true, "telemetry.enable() resumes it immediately")

    local report = t.report()
    H.eq(report.disabled, false, "report reflects the enabled state")

    telemetry.disable(namespace)
    H.eq(t.report().disabled, true, "report reflects the disabled state")

    t.unwrap()
    telemetry.enable(namespace) -- leave no persisted disable behind for this dir
  end

  -- -------------------------------------------------------------------------
  -- :LibTelemetry — per-namespace start/stop/reset leave other instances alone
  -- -------------------------------------------------------------------------
  do
    require("lib.nvim.telemetry.command").setup()

    local ns_a, ns_b = ns("cmd_a"), ns("cmd_b")
    local mod_a, mod_b = { f = function() end }, { g = function() end }
    local ta = telemetry.new({ namespace = ns_a, persist = false })
    local tb = telemetry.new({ namespace = ns_b, persist = false })
    ta.wrap(mod_a)
    tb.wrap(mod_b)
    ta.start()
    tb.start()
    mod_a.f()
    mod_b.g()

    vim.cmd("LibTelemetry stop " .. ns_a)
    H.eq(ta.is_running(), false, ":LibTelemetry stop <ns> stops only that instance")
    H.eq(tb.is_running(), true, "the other instance keeps running")

    vim.cmd("LibTelemetry start " .. ns_a)
    H.eq(ta.is_running(), true, ":LibTelemetry start <ns> restarts only that instance")

    vim.cmd("LibTelemetry reset " .. ns_a)
    H.eq(ta.report().total_calls, 0, ":LibTelemetry reset <ns> clears only that instance")
    H.eq(tb.report().total_calls, 1, "the other instance's data is untouched")

    -- Second-argument completion offers namespaces, not the subcommand list.
    local completions = vim.fn.getcompletion("LibTelemetry stop ", "cmdline")
    H.ok(vim.tbl_contains(completions, ns_a), "namespace offered after 'stop '")
    H.eq(vim.tbl_contains(completions, "start"), false, "subcommands not repeated as a 2nd arg")

    local ok = pcall(vim.cmd, "LibTelemetry stop does-not-exist")
    H.eq(ok, true, "an unknown namespace warns rather than erroring")

    ta.unwrap()
    tb.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- :LibTelemetry disable/enable/disabled — dir=tmpdir, isolated from the
  -- real stdpath("cache") the same way the toggle tests above are.
  -- -------------------------------------------------------------------------
  do
    local ns_a, ns_b = ns("cmd_disable_a"), ns("cmd_disable_b")
    local mod_a, mod_b = { f = function() end }, { g = function() end }
    local ta = telemetry.new({ namespace = ns_a, persist = false, dir = tmpdir })
    local tb = telemetry.new({ namespace = ns_b, persist = false, dir = tmpdir })
    ta.wrap(mod_a)
    tb.wrap(mod_b)
    ta.start()
    tb.start()

    vim.cmd("LibTelemetry disable " .. ns_a)
    H.eq(ta.is_running(), false, ":LibTelemetry disable <ns> stops that instance now")
    H.eq(tb.is_running(), true, "the other instance is untouched")
    H.eq(ta.start(), false, "start() stays a no-op while disabled, even called directly")

    local disabled_lines = {}
    local ok_report = pcall(function()
      disabled_lines = ta.report()
    end)
    H.eq(ok_report, true, "report() does not throw on a disabled instance")
    H.eq(disabled_lines.disabled, true, "report marks it disabled")

    vim.cmd("LibTelemetry enable " .. ns_a)
    H.eq(ta.is_running(), true, ":LibTelemetry enable <ns> resumes it now")

    local ok_unknown = pcall(vim.cmd, "LibTelemetry disable does-not-exist")
    H.eq(ok_unknown, true, "disabling an unknown/not-yet-loaded namespace does not error")

    ta.unwrap()
    tb.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- report.markdown(): the same report data M.lines renders, as GFM instead
  -- of terminal box-drawing. Built from the same M.build() result, so it
  -- cannot report different numbers than M.lines does.
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("markdown")
    local mod = {
      find = function(path)
        return path
      end,
      quiet = function() end,
    }
    local t = telemetry.new({ namespace = namespace, persist = false })
    t.wrap(mod, "fs")
    t.start({ profile_args = { "fs.find" } })
    for _ = 1, 25 do
      mod.find("/repo/lib.nvim")
    end
    mod.find("/repo/other")
    mod.quiet()

    local text = table.concat(t.markdown(), "\n")
    H.ok(text:find("# " .. namespace .. " — telemetry", 1, true) ~= nil, "H1 names the namespace")
    H.ok(text:find("| Function | Calls | Ø ms | Errors |", 1, true) ~= nil, "table header present")
    H.ok(text:find("`fs.find`", 1, true) ~= nil, "busiest entry rendered as a table row")
    H.ok(
      text:find("### `fs.find` — argument profile", 1, true) ~= nil,
      "argument-profile subsection for a profiled function"
    )
    H.ok(text:find("candidate for", 1, true) ~= nil, "memoization hint carried into a blockquote")
    H.eq(
      text:find("### `fs.quiet`", 1, true),
      nil,
      "no argument-profile subsection for an unprofiled function"
    )

    t.stop()
    t.unwrap()
  end

  do
    local t = telemetry.new({ namespace = ns("markdown_empty"), persist = false })
    H.ok(
      vim.tbl_contains(t.markdown(), "_(no calls recorded)_"),
      "empty instance renders the no-data line, not an empty table"
    )
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- markdown_all(): combined document, one H1, each report's own heading
  -- demoted to H2 so the result is one well-formed file.
  -- -------------------------------------------------------------------------
  do
    local ns_a, ns_b = ns("md_all_a"), ns("md_all_b")
    local mod_a, mod_b = { f = function() end }, { g = function() end }
    local ta = telemetry.new({ namespace = ns_a, persist = false })
    local tb = telemetry.new({ namespace = ns_b, persist = false })
    ta.wrap(mod_a)
    tb.wrap(mod_b)
    ta.start()
    tb.start()
    mod_a.f()
    mod_b.g()

    local lines = telemetry.markdown_all()
    local text = table.concat(lines, "\n")
    H.eq(lines[1], "# lib.nvim — telemetry", "one combined H1")
    H.eq(text:find("\n# ", 1, true), nil, "no second H1 -- per-report headings are demoted")
    H.ok(
      text:find("## " .. ns_a .. " — telemetry", 1, true) ~= nil,
      "first namespace's heading demoted to H2"
    )
    H.ok(
      text:find("## " .. ns_b .. " — telemetry", 1, true) ~= nil,
      "second namespace's heading demoted to H2"
    )
    H.ok(text:find("\n---\n", 1, true) ~= nil, "reports separated by a thematic break")

    ta.stop()
    tb.stop()
    ta.unwrap()
    tb.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- report_file.lua: path resolution (dir-overridable, mirrors store.lua's
  -- own sanitize/cache_key convention) and best-effort disk writes.
  -- -------------------------------------------------------------------------
  do
    local report_file = require("lib.nvim.telemetry.report_file")

    H.eq(report_file.dir({ dir = tmpdir }):sub(1, #tmpdir), tmpdir, "dir override is honored")
    H.ok(
      report_file.dir({ dir = tmpdir }):find("telemetry", 1, true) ~= nil,
      "lives under a telemetry/ subdir"
    )
    H.eq(
      report_file.namespace_path("lib.nvim", { dir = tmpdir }),
      report_file.dir({ dir = tmpdir }) .. "/lib.nvim.md",
      "namespace path is sanitize(namespace).md under dir()"
    )
    H.eq(
      report_file.combined_path({ dir = tmpdir }),
      report_file.dir({ dir = tmpdir }) .. "/report.md",
      "combined path is report.md under dir()"
    )

    local path = report_file.dir({ dir = tmpdir }) .. "/write_test.md"
    local ok, err = report_file.write(path, { "# hello", "", "world" })
    H.eq(ok, true, "write succeeds")
    H.eq(err, nil, "no error on success")

    local file = io.open(path, "r")
    H.ok(file ~= nil, "the file exists")
    local content = file:read("*a")
    file:close()
    H.eq(content, "# hello\n\nworld\n", "content round-trips, trailing newline added")
  end

  -- -------------------------------------------------------------------------
  -- report_file = true: keep this namespace's Markdown report on disk,
  -- rewritten at every flush -- what makes the mdview bridge self-updating.
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("report_file_opt")
    local report_file = require("lib.nvim.telemetry.report_file")
    local mod = { f = function() end }

    local t = telemetry.new({
      namespace = namespace,
      persist = false,
      dir = tmpdir,
      report_file = true,
    })
    t.wrap(mod)
    t.start()
    mod.f()
    t.flush()

    local path = report_file.namespace_path(namespace, { dir = tmpdir })
    local file = io.open(path, "r")
    H.ok(file ~= nil, "report_file = true writes a per-namespace file at flush")
    local content = file:read("*a")
    file:close()
    H.ok(content:find("| `f` | 1 |", 1, true) ~= nil, "the written report reflects current counts")

    mod.f()
    t.flush()
    local file2 = io.open(path, "r")
    local content2 = file2:read("*a")
    file2:close()
    H.ok(
      content2:find("| `f` | 2 |", 1, true) ~= nil,
      "rewritten on the next flush with updated counts"
    )

    t.stop()
    t.unwrap()
  end

  do
    local namespace = ns("report_file_off")
    local report_file = require("lib.nvim.telemetry.report_file")
    local mod = { f = function() end }
    local t = telemetry.new({ namespace = namespace, persist = false, dir = tmpdir })
    t.wrap(mod)
    t.start()
    mod.f()
    t.flush()

    local path = report_file.namespace_path(namespace, { dir = tmpdir })
    H.eq(io.open(path, "r"), nil, "no file written when report_file is left at its false default")
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- report_style resolution: mdview.nvim is not on this test run's runtime
  -- path (docs/TESTS/run.lua only appends the lib.nvim repo itself), so
  -- "mdview"/"auto" deterministically fall back to "kit" here -- exactly the
  -- degrade-silently path a consumer without mdview installed hits for real.
  -- -------------------------------------------------------------------------
  do
    local resolve_style = require("lib.nvim.telemetry.report_style")
    local mdview_renderer = require("lib.nvim.telemetry.renderers.mdview")

    H.eq(mdview_renderer.available(), false, "mdview.nvim is not on rtp in this test run")

    H.eq(resolve_style("kit"), "kit", "explicit kit stays kit")
    H.eq(resolve_style("file"), "file", "explicit file stays file")
    H.eq(resolve_style("mdview"), "kit", "explicit mdview degrades to kit when unavailable")
    H.eq(resolve_style("auto"), "kit", "auto degrades to kit when mdview is unavailable")
    H.eq(resolve_style(nil), "kit", "nil behaves like auto")
    H.eq(resolve_style("nonsense"), "kit", "an unrecognized value behaves like auto")

    local ok, err = mdview_renderer.open({ "x" }, tmpdir .. "/mdview_open_test.md")
    H.eq(ok, false, "mdview.open() fails cleanly, not raising, when mdview is unavailable")
    H.ok(err ~= nil, "...with an explanatory error")
  end

  -- -------------------------------------------------------------------------
  -- telemetry.setup({ report_style = ... }): the one module-level default,
  -- separate from telemetry.new(opts) -- see config.lua for why.
  -- -------------------------------------------------------------------------
  do
    local config = require("lib.nvim.telemetry.config")
    H.eq(config.report_style(), "auto", "auto is the default")
    telemetry.setup({ report_style = "file" })
    H.eq(config.report_style(), "file", "setup() overrides the module-level default")
    telemetry.setup({ report_style = "auto" })
    H.eq(config.report_style(), "auto", "setup() again restores it for the rest of this run")
  end

  -- -------------------------------------------------------------------------
  -- :LibTelemetry export — format inferred from the target path's extension,
  -- not a separate flag (this command's argument parsing stays positional).
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("export")
    local mod = { f = function() end }
    local t = telemetry.new({ namespace = namespace, persist = false })
    t.wrap(mod)
    t.start()
    mod.f()

    local md_path = tmpdir .. "/export_test.md"
    vim.cmd("LibTelemetry export " .. md_path)
    local md_file = io.open(md_path, "r")
    H.ok(md_file ~= nil, "export writes a .md path as Markdown")
    local md_content = md_file:read("*a")
    md_file:close()
    H.ok(
      md_content:find("# lib.nvim — telemetry", 1, true) ~= nil,
      "combined Markdown document, same shape as markdown_all()"
    )

    local json_path = tmpdir .. "/export_test.json"
    vim.cmd("LibTelemetry export " .. json_path)
    local json_file = io.open(json_path, "r")
    H.ok(json_file ~= nil, "export writes a .json path as JSON (unchanged default behavior)")
    local json_content = json_file:read("*a")
    json_file:close()
    local ok_decode, decoded = pcall(vim.json.decode, json_content)
    H.eq(ok_decode, true, "the .json export is still valid JSON")
    H.ok(decoded.reports ~= nil, "...with the expected top-level shape")

    t.stop()
    t.unwrap()
  end

  -- -------------------------------------------------------------------------
  -- :LibTelemetry open [ns] — forces a flush, then dispatches per
  -- report_style. "mdview" falls back to "kit" here since mdview is
  -- unavailable in this test run (see report_style resolution tests above).
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("open")
    local mod = { f = function() end }
    local t = telemetry.new({ namespace = namespace, persist = false, dir = tmpdir })
    t.wrap(mod)
    t.start()
    mod.f()

    telemetry.setup({ report_style = "kit" })
    local ok = pcall(vim.cmd, "LibTelemetry open " .. namespace)
    H.eq(ok, true, ":LibTelemetry open <ns> does not error with report_style = kit")

    telemetry.setup({ report_style = "file" })
    ok = pcall(vim.cmd, "LibTelemetry open " .. namespace)
    H.eq(ok, true, ":LibTelemetry open <ns> does not error with report_style = file")
    local report_file = require("lib.nvim.telemetry.report_file")
    local path = report_file.namespace_path(namespace, { dir = tmpdir })
    H.ok(io.open(path, "r") ~= nil, "report_style = file wrote the per-namespace report")

    telemetry.setup({ report_style = "mdview" })
    ok = pcall(vim.cmd, "LibTelemetry open " .. namespace)
    H.eq(
      ok,
      true,
      "report_style = mdview falls back to the kit float without erroring when mdview is unavailable"
    )

    ok = pcall(vim.cmd, "LibTelemetry open does-not-exist")
    H.eq(ok, true, "an unknown namespace warns rather than erroring")

    ok = pcall(vim.cmd, "LibTelemetry open")
    H.eq(ok, true, "bare open (every instance, combined) does not error")

    telemetry.setup({ report_style = "auto" }) -- restore default for any later spec
    t.stop()
    t.unwrap()
  end

  do
    local completions = vim.fn.getcompletion("LibTelemetry open ", "cmdline")
    H.eq(
      vim.tbl_contains(completions, "open"),
      false,
      "subcommands not repeated as a 2nd arg after open"
    )

    local first_token_completions = vim.fn.getcompletion("LibTelemetry o", "cmdline")
    H.ok(vim.tbl_contains(first_token_completions, "open"), "open is offered as a subcommand")
  end

  vim.fn.delete(tmpdir, "rf")
end
