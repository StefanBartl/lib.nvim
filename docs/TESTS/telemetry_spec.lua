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

  vim.fn.delete(tmpdir, "rf")
end
