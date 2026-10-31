-- TESTS/patterns_hardening_spec.lua — regressions for the security / robustness / performance audit of
-- the pattern modules (hostile or odd input, option validation, bounded resources, O(1) bookkeeping).
return function(H)
  local eq, ok = H.eq, H.ok

  local function raises(fn, ...)
    return not pcall(fn, ...)
  end

  -- ------------------------------------------------------------------ flyweight
  do
    local flyweight = require("lib.lua.patterns.flyweight")
    -- tostring(table) is an address that is reused after a collection: keys must be identities
    local made = 0
    local fw = flyweight.new(function(t)
      made = made + 1
      return { name = t.name }
    end)
    local wrong = 0
    for i = 1, 3000 do
      local t = { name = "k" .. i }
      if fw:get(t).name ~= "k" .. i then
        wrong = wrong + 1
      end
      if i % 200 == 0 then
        collectgarbage()
      end
    end
    eq(wrong, 0, "flyweight: a new table never gets the instance of a collected one")
    eq(made, 3000, "flyweight: every distinct table made its own instance")

    local same = { name = "same" }
    ok(fw:get(same) == fw:get(same), "flyweight: the same table shares its instance")

    local prim = flyweight.new(function(v)
      return { v }
    end)
    ok(prim:get(1) ~= prim:get("1"), "flyweight fast path: 1 and '1' differ")
    ok(prim:get("a") == prim:get("a"), "flyweight fast path: equal strings share")
    ok(prim:get(true) ~= prim:get("true"), "flyweight fast path: boolean and string differ")
    local nan = 0 / 0
    ok(
      prim:get(nan) ~= prim:get(nan),
      "flyweight fast path: NaN is never cached (it cannot be a key)"
    )
    eq(prim:size(), 5, "flyweight: size counts the fast cache (1, '1', 'a', true, 'true')")
    prim:clear()
    eq(prim:size(), 0, "flyweight: clear empties both caches")
  end

  -- ------------------------------------------------------------------ throttle
  do
    local throttle = require("lib.nvim.patterns.throttle")
    for _, bad in ipairs({ -1, 0 / 0, math.huge, "x", {} }) do
      ok(raises(throttle.new, function() end, bad), "throttle.new rejects ms = " .. tostring(bad))
    end
    ok(raises(throttle.new, function() end, nil), "throttle.new rejects a missing ms")
    local t = throttle.new(function() end, 0)
    t.cancel()
    ok(true, "throttle.new accepts ms = 0")
  end

  -- ------------------------------------------------------------------ retry_backoff
  do
    local retry = require("lib.nvim.patterns.retry_backoff")
    eq(retry.delay(1, { base_ms = -100 }), 0, "retry delay: negative becomes 0")
    eq(retry.delay(1, { base_ms = 0 / 0 }), 0, "retry delay: NaN becomes 0")
    eq(
      retry.delay(2, { factor = -2, base_ms = 10 }),
      0,
      "retry delay: negative factor cannot go below 0"
    )
    ok(
      raises(retry.run, function() end, { base_ms = "x" }),
      "retry.run rejects a non-number base_ms"
    )
    ok(
      raises(retry.run, function() end, { max_attempts = 0 }),
      "retry.run rejects max_attempts < 1"
    )
    ok(raises(retry.run, function() end, { max_ms = 0 / 0 }), "retry.run rejects NaN max_ms")

    ok(
      raises(retry.run, function() end, { base_ms = -100 }),
      "retry.run rejects a negative base_ms"
    )

    local result
    retry.run(function(_, done)
      done(false, "x")
    end, {
      max_attempts = 3,
      factor = 0,
      sleep = function(_, cb)
        cb()
      end,
      on_done = function(o, res, n)
        result = { o, res, n }
      end,
    })
    ok(
      result and not result[1] and result[3] == 3,
      "a factor of 0 (delay 0 from the second retry on) still ends with on_done"
    )

    result = nil
    retry.run(function(_, done)
      done(false, "x")
    end, {
      sleep = function()
        error("cannot schedule", 0)
      end,
      on_done = function(o, res)
        result = { o, res }
      end,
    })
    ok(
      result and not result[1] and result[2] == "cannot schedule",
      "a failing sleep ends the retry with that error"
    )
  end

  -- ------------------------------------------------------------------ iterator
  do
    local iterator = require("lib.lua.patterns.iterator")
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge }) do
      ok(raises(iterator.range, 1, 5, bad), "range rejects step " .. tostring(bad))
      ok(raises(iterator.range, bad, 5), "range rejects first " .. tostring(bad))
      ok(raises(iterator.range, 1, bad), "range rejects last " .. tostring(bad))
    end
    eq(
      #iterator.range(0, 0.3, 0.1):collect(),
      4,
      "range: float steps do not drift (0, 0.1, 0.2, 0.3)"
    )
    local big = #iterator.range(2 ^ 53, 2 ^ 53 + 3):collect()
    ok(big >= 1 and big <= 6, "range terminates at 2^53 (2^53 + 3 is not representable)")
    ok(
      raises(function()
        iterator.range(1, 3):take(0 / 0)
      end),
      "take(NaN) raises"
    )
    eq(#iterator.range(1, 10):take(2.5):collect(), 2, "take floors a fractional count")
    eq(#iterator.range(1, 10):drop(2.5):collect(), 8, "drop floors a fractional count")
    eq(#iterator.range(1, 10):take(-3):collect(), 0, "a negative take yields nothing")
  end

  -- ------------------------------------------------------------------ command
  do
    local command = require("lib.lua.patterns.command")
    local h = command.history()
    local second = { name = "second", run = function() end, undo = function() end }
    local first = {
      name = "first",
      run = function() end,
      undo = function()
        h:run(second)
      end,
    }
    h:run(first)
    eq(h:undo(), "first", "undo returns the name")
    eq(
      table.concat(h:names(), ","),
      "second",
      "a command run by undo stays, the undone one is not duplicated"
    )
    eq(h:redo(), "first", "the undone command is the one on the redo stack")

    for _, bad in ipairs({ 0, 0 / 0, "x", math.huge, -1 }) do
      ok(raises(command.history, { limit = bad }), "history rejects limit " .. tostring(bad))
    end
    local w = command.history({ limit = 3.9 })
    for i = 1, 10 do
      w:run({ name = "c" .. i, run = function() end })
    end
    eq(
      table.concat(w:names(), ","),
      "c8,c9,c10",
      "the window keeps the last `limit` commands (fractional limit floors)"
    )
    w:undo()
    w:undo()
    w:undo()
    ok(not w:can_undo(), "undoing the whole window empties it")
    w:run({ name = "again", run = function() end })
    eq(table.concat(w:names(), ","), "again", "the window works after it was emptied")
  end

  -- ------------------------------------------------------------------ prototype
  do
    local prototype = require("lib.lua.patterns.prototype")
    local Base = { opts = { x = 1 } }
    local template = setmetatable({}, { __index = Base })
    local p = prototype.new(template)
    local c = p:clone({ opts = { x = 2 } })
    eq(Base.opts.x, 1, "clone does not write through the template's __index into shared state")
    eq(c.opts.x, 2, "the override is applied to the clone")

    local shared = { color = "red" }
    local aliased = prototype.new({ a = shared, b = shared })
    local d = aliased:clone({ a = { color = "blue" } })
    eq(d.a.color, "blue", "aliased: the overridden entry changed")
    eq(d.b.color, "red", "aliased: the other alias is untouched")
    eq(shared.color, "red", "aliased: the original is untouched")
  end

  -- ------------------------------------------------------------------ unit_of_work
  do
    local repository = require("lib.lua.patterns.repository")
    local unit_of_work = require("lib.lua.patterns.unit_of_work")
    local store = repository.memory()
    local flaky = {
      get = function(id)
        if id == "bad" then
          error("get broke", 0)
        end
        return store.get(id)
      end,
      put = store.put,
      delete = store.delete,
    }
    local u = unit_of_work.new(flaky)
    u:add("a", 1):add("bad", 2):add("c", 3)
    local committed, err, step = u:commit()
    ok(not committed and err == "get broke" and step == 2, "commit reports a get that raises")
    eq(store.get("a"), nil, "and the already applied step is reverted")
    eq(u:pending(), 0, "and the queue is cleared, so a retry does not double-apply")
  end

  -- ------------------------------------------------------------------ object_pool
  do
    local object_pool = require("lib.lua.patterns.object_pool")
    local pool = object_pool.new({
      create = function()
        return {}
      end,
    })
    local o = pool:acquire()
    pool:release(o)
    pool:release(o)
    ok(pool:acquire() ~= pool:acquire(), "a double release does not hand the object out twice")

    for _, bad in ipairs({ 0 / 0, "8", -1 }) do
      ok(
        raises(object_pool.new, {
          create = function()
            return {}
          end,
          max = bad,
        }),
        "pool rejects max " .. tostring(bad)
      )
    end

    local fails = true
    local p2 = object_pool.new({
      create = function()
        if fails then
          error("no", 0)
        end
        return {}
      end,
    })
    ok(raises(p2.acquire, p2), "a failing create raises")
    eq(p2:stats().created, 0, "and does not count as created")
    local seen
    local p3 = object_pool.new({
      create = function()
        return { 1 }
      end,
    })
    eq(
      p3:with(function(t)
        seen = t
        return "a", nil, "c"
      end),
      "a",
      "with returns the callback results"
    )
    eq(
      select(
        "#",
        p3:with(function()
          return 1, nil, nil
        end)
      ),
      3,
      "with keeps trailing nil results"
    )
    ok(seen ~= nil, "with passed an object")
  end

  -- ------------------------------------------------------------------ nil errors
  do
    local event_bus = require("lib.lua.patterns.event_bus")
    local bus = event_bus.new()
    bus:on("t", function()
      error(nil)
    end)
    local _, errs = bus:emit("t")
    eq(errs[1], "nil error", "event_bus: error(nil) is reported")

    local chain = require("lib.lua.patterns.chain_of_responsibility").new()
    chain:add("x", function()
      error(nil)
    end)
    local _, _, _, cerrs = chain:handle("r")
    eq(cerrs[1], "nil error", "chain: error(nil) is reported")

    local m = require("lib.lua.patterns.mediator").new()
    m:register("x", {
      handle = function()
        error(nil)
      end,
    })
    local _, merrs = m:broadcast("other", "msg")
    eq(merrs[1], "nil error", "mediator: error(nil) is reported")
  end

  -- ------------------------------------------------------------------ event_bus bookkeeping
  do
    local event_bus = require("lib.lua.patterns.event_bus")
    local bus = event_bus.new()
    local order = {}
    bus:on("t", function()
      order[#order + 1] = "a"
      bus:clear("t")
    end)
    bus:on("t", function()
      order[#order + 1] = "b"
    end)
    bus:emit("t")
    eq(table.concat(order, ","), "a", "clear(topic) inside an emit stops the remaining listeners")

    -- many subscribe / unsubscribe in odd order, the survivors are still called, once each
    local b2 = event_bus.new()
    local calls, offs = {}, {}
    for i = 1, 600 do
      offs[i] = b2:on("t", function()
        calls[i] = (calls[i] or 0) + 1
      end)
    end
    for i = 1, 600 do
      if i % 3 ~= 0 then
        offs[i]()
      end
    end
    eq(b2:count("t"), 200, "count is exact after many unsubscribes")
    b2:emit("t")
    local wrong = 0
    for i = 1, 600 do
      local expected = (i % 3 == 0) and 1 or nil
      if calls[i] ~= expected then
        wrong = wrong + 1
      end
    end
    eq(wrong, 0, "exactly the survivors were called, once")

    -- once listeners leave nothing behind
    local b3 = event_bus.new()
    for i = 1, 500 do
      b3:once("topic-" .. i, function() end)
      b3:emit("topic-" .. i)
    end
    eq(next(b3.topics), nil, "topics without listeners are dropped")
    local fired = 0
    for _ = 1, 2000 do
      b3:once("batch", function()
        fired = fired + 1
      end)
    end
    b3:emit("batch")
    eq(fired, 2000, "2000 once listeners all fired")
    eq(b3:count("batch"), 0, "and none is left")
    eq(next(b3.topics), nil, "the emptied topic is dropped")

    -- a listener added during an emit does not run in that emit
    local b4 = event_bus.new()
    local late = 0
    b4:on("t", function()
      b4:on("t", function()
        late = late + 1
      end)
    end)
    b4:emit("t")
    eq(late, 0, "a listener added during the emit is not called by it")
    b4:emit("t")
    eq(late, 1, "but by the next one")
  end

  -- ------------------------------------------------------------------ composite
  do
    local composite = require("lib.lua.patterns.composite")
    local group
    local a = {
      f = function(self)
        group:remove(self)
      end,
    }
    local called = false
    local b = {
      f = function()
        called = true
        return 1
      end,
    }
    group = composite.new({ a, b })
    group:call("f")
    ok(called, "a child that removes itself does not make the group skip its sibling")
    eq(group:size(), 1, "and it is removed")
  end

  -- ------------------------------------------------------------------ chain bookkeeping
  do
    local cor = require("lib.lua.patterns.chain_of_responsibility")
    local chain = cor.new()
    chain:add("a", function()
      chain:add("late", function()
        return true, "late"
      end)
    end)
    local handled = chain:handle("x")
    ok(not handled, "a handler added during handle() is not offered the current request")
    local h2, r2 = chain:handle("x")
    ok(h2 and r2 == "late", "but the next request")
    ok(chain:remove("late") and not chain:remove("late"), "remove by name")
    eq(table.concat(chain:names(), ","), "a", "names after remove")
    chain:add("a", function()
      return true, "replaced"
    end)
    eq(table.concat(chain:names(), ","), "a", "re-adding a name replaces it")
    eq(select(2, chain:handle("x")), "replaced", "the replacement answers")
  end

  -- ------------------------------------------------------------------ state_machine
  do
    local state_machine = require("lib.lua.patterns.state_machine")
    local sm
    sm = state_machine.new({
      initial = "a",
      transitions = {
        {
          from = "a",
          event = "go",
          to = "b",
          action = function()
            sm:fire("jump")
          end,
        },
        { from = "a", event = "jump", to = "c" },
      },
    })
    ok(raises(sm.fire, sm, "go"), "fire() inside an action is rejected")
    eq(sm:state(), "c", "the nested transition stands, the outer one did not overwrite it")
  end

  -- ------------------------------------------------------------------ small constructors
  do
    local f = function() end
    local abstract_factory = require("lib.lua.patterns.abstract_factory")
    ok(
      raises(abstract_factory.new, { A = { ["a,b"] = f }, B = { a = f, b = f } }),
      "abstract_factory: product names with a comma cannot hide a mismatch"
    )

    local factory_method = require("lib.lua.patterns.factory_method")
    local fm = factory_method.new({ a = f })
    ok(raises(fm.register, fm, 5, f), "factory_method: a non-string kind raises")
    eq(table.concat(fm:kinds(), ","), "a", "and leaves no phantom kind")

    local repository = require("lib.lua.patterns.repository")
    local store = repository.memory()
    ok(raises(store.put, "x", nil), "memory store: nil value raises")
    ok(raises(store.put, 0 / 0, 1), "memory store: NaN id raises")
    eq(#store.all(), 0, "and nothing phantom is listed")

    local di = require("lib.lua.patterns.dependency_injection")
    local runs = 0
    local c = di.new()
    c:provide("nothing", function()
      runs = runs + 1
      return nil
    end)
    c:resolve("nothing")
    c:resolve("nothing")
    eq(runs, 1, "dependency_injection: a factory that returns nil is cached")

    local decorator = require("lib.lua.patterns.decorator")
    local timed = decorator.timed(function()
      error("sink broke", 0)
    end, function()
      return 0
    end)(function()
      return "result"
    end)
    eq(timed(), "result", "decorator.timed: a raising sink does not replace the result")

    local circuit_breaker = require("lib.lua.patterns.circuit_breaker")
    for _, bad in ipairs({
      { threshold = 0 },
      { threshold = 0 / 0 },
      { threshold = "x" },
      { reset_ms = 0 / 0 },
      { reset_ms = -1 },
    }) do
      ok(raises(circuit_breaker.new, bad), "circuit_breaker rejects " .. vim.inspect(bad))
    end
  end

  -- ------------------------------------------------------------------ repository bookkeeping
  do
    local repository = require("lib.lua.patterns.repository")
    local store = repository.memory()
    local repo = repository.new(store)
    for i = 1, 400 do
      repo:save("k" .. i, i)
    end
    for i = 1, 400 do
      if i % 2 == 1 then
        repo:remove("k" .. i)
      end
    end
    eq(repo:count(), 200, "count after many deletes")
    local all = repo:all()
    eq(#all, 200, "all after many deletes")
    eq(all[1].id, "k2", "order is kept across compaction (first)")
    eq(all[200].id, "k400", "order is kept across compaction (last)")
    repo:save("late", 1)
    eq(repo:all()[201].id, "late", "a new entry goes to the end")
    eq(
      repo:find(function(v)
        return v == 6
      end).id,
      "k6",
      "find uses the store iteration"
    )
    eq(#repo:filter(function(v)
      return v % 4 == 0
    end), 100, "filter uses the store iteration")
    repo:remove("late")
    repo:remove("late")
    eq(repo:count(), 200, "removing twice is harmless")

    local counted = 0
    local legacy = repository.new({
      get = function() end,
      put = function() end,
      delete = function() end,
      all = function()
        counted = counted + 1
        return { { id = 1, value = 1 }, { id = 2, value = 2 } }
      end,
    })
    eq(legacy:count(), 2, "a store without count() falls back to all()")
    eq(
      legacy:find(function(v)
        return v == 2
      end).id,
      2,
      "a store without each() falls back to all()"
    )
    ok(counted == 2, "the fallback was used")
  end

  -- ------------------------------------------------------------------ facade
  do
    local facade = require("lib.lua.patterns.facade")
    ok(raises(facade.new, { a = 5 }), "facade: a non-string entry raises")
    ok(raises(facade.new, { a = "x:y:z" }), "facade: module:function:extra raises")
    ok(raises(facade.new, { a = "" }), "facade: an empty entry raises")
    package.preload["hardening_spec.mod"] = function()
      return { present = function() end }
    end
    local api =
      facade.new({ ok_fn = "hardening_spec.mod:present", gone = "hardening_spec.mod:absent" })
    ok(type(api.ok_fn) == "function", "facade: an existing function resolves")
    ok(
      raises(function()
        return api.gone
      end),
      "facade: a missing function raises instead of returning nil"
    )
    package.preload["hardening_spec.mod"] = nil
    package.loaded["hardening_spec.mod"] = nil
  end

  -- ------------------------------------------------------------------ state
  do
    local state = require("lib.lua.patterns.state")
    local f = function() end
    ok(
      raises(state.new, { initial = "a", states = { a = {} }, fields = { _current = "x" } }),
      "state: reserved field _current raises"
    )
    ok(
      raises(state.new, { initial = "a", states = { a = {} }, fields = { _states = {} } }),
      "state: reserved field _states raises"
    )
    ok(
      raises(state.new, { initial = "a", states = { a = { set_state = f } } }),
      "state: a state cannot shadow set_state"
    )
    local one = state.new({
      initial = "a",
      states = {
        a = {
          ping = function()
            return "a"
          end,
        },
        b = {
          ping = function()
            return "b"
          end,
        },
      },
    })
    local two = state.new({
      initial = "b",
      states = {
        a = {
          ping = function()
            return "a"
          end,
        },
        b = {
          ping = function()
            return "b"
          end,
        },
      },
    })
    eq(one:ping() .. two:ping(), "ab", "state: the shared dispatcher still dispatches per object")
  end

  -- ------------------------------------------------------------------ aggregators
  do
    local lua_patterns = require("lib.lua.patterns")
    eq(lua_patterns.nope, nil, "aggregator: an unknown name is nil")
    eq(
      lua_patterns["result.@types"],
      nil,
      "aggregator: a dotted key is nil, it cannot reach other modules"
    )
    eq(lua_patterns[".."], nil, "aggregator: '..' is nil")
    ok(
      lua_patterns.result ~= nil and lua_patterns.result == require("lib.lua.patterns.result"),
      "aggregator: a real module loads"
    )
    local nvim_patterns = require("lib.nvim.patterns")
    eq(nvim_patterns.nope, nil, "nvim aggregator: an unknown name is nil")
    ok(nvim_patterns.throttle ~= nil, "nvim aggregator: a real module loads")
  end

  -- ------------------------------------------------------------------ decorator.after args
  do
    local decorator = require("lib.lua.patterns.decorator")
    local seen
    local f = decorator.wrap(
      function(a, b)
        return a + b
      end,
      decorator.after(function(results, a, b)
        seen = { results[1], a, b }
      end)
    )
    eq(f(2, 3), 5, "decorator.after: result unchanged")
    ok(
      seen[1] == 5 and seen[2] == 2 and seen[3] == 3,
      "decorator.after: the hook still gets results and arguments"
    )
  end
end
