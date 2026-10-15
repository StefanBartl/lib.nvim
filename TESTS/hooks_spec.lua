-- TESTS/hooks_spec.lua — lib.nvim.hooks: order, priority, veto, error isolation, unregister, unknown events.

return function(H)
  local eq, ok = H.eq, H.ok
  local hooks = require("lib.nvim.hooks")

  local errors = {}
  local function new(extra)
    errors = {}
    return hooks.new(vim.tbl_extend("force", {
      events = { "before_apply", "after_apply", "before_write", "after_write" },
      on_error = function(event, err)
        errors[#errors + 1] = event .. ":" .. tostring(err)
      end,
    }, extra or {}))
  end

  -- Order: `extra` (config hooks) first, then registered ones by priority, ties in registration order.
  do
    local reg = new()
    local seen = {}
    local function rec(tag)
      return function()
        seen[#seen + 1] = tag
      end
    end
    reg.on("after_apply", rec("late"), { priority = 10 })
    reg.on("after_apply", rec("a"))
    reg.on("after_apply", rec("early"), { priority = -5 })
    reg.on("after_apply", rec("b"))
    reg.run("after_apply", {}, { rec("cfg1"), rec("cfg2") })
    eq(
      table.concat(seen, ","),
      "cfg1,cfg2,early,a,b,late",
      "order: config hooks, then priority, then registration"
    )

    seen = {}
    reg.run("after_apply", {}, rec("single"))
    eq(seen[1], "single", "extra may be a single function")
  end

  -- ctx is passed through; an event nobody listens to proceeds.
  do
    local reg = new()
    local got
    reg.on("before_apply", function(ctx)
      got = ctx
    end)
    local ctx = { file = "a.lua" }
    local proceed, errs = reg.run("before_apply", ctx)
    eq(got, ctx, "ctx reaches the hook")
    eq(proceed, true, "no veto: proceed")
    eq(errs, 0, "no errors")
    eq(select(1, reg.run("after_write", {})), true, "an event without hooks proceeds")
  end

  -- Veto: only `false` vetoes; every hook still runs; non-vetoable events ignore it.
  do
    local reg = new()
    local ran = {}
    reg.on("before_apply", function()
      ran[#ran + 1] = 1
      return false
    end)
    reg.on("before_apply", function()
      ran[#ran + 1] = 2
      return nil
    end)
    local proceed = reg.run("before_apply", {})
    eq(proceed, false, "veto: a hook returned false")
    eq(table.concat(ran, ","), "1,2", "veto: the later hook still runs")

    local reg2 = new()
    reg2.on("before_apply", function()
      return 0
    end)
    reg2.on("before_apply", function()
      return ""
    end)
    eq(select(1, reg2.run("before_apply", {})), true, "only exactly false vetoes")

    local reg3 = new()
    reg3.on("after_apply", function()
      return false
    end)
    eq(select(1, reg3.run("after_apply", {})), true, "a non-vetoable event ignores false")
    local reg4 = new({ vetoable = { "after_write" } })
    reg4.on("after_write", function()
      return false
    end)
    reg4.on("before_write", function()
      return false
    end)
    eq(select(1, reg4.run("after_write", {})), false, "vetoable = { ... } makes it vetoable")
    eq(
      select(1, reg4.run("before_write", {})),
      true,
      "vetoable = { ... } replaces the before_ default"
    )

    local reg5 = new({ short_circuit = true })
    local seen = {}
    reg5.on("before_apply", function()
      seen[#seen + 1] = "first"
      return false
    end)
    reg5.on("before_apply", function()
      seen[#seen + 1] = "second"
    end)
    eq(select(1, reg5.run("before_apply", {})), false, "short_circuit: vetoed")
    eq(table.concat(seen, ","), "first", "short_circuit: stops at the first veto")
  end

  -- Error isolation: a throwing hook is reported, the others run, no veto comes from it.
  do
    local reg = new()
    local ran = {}
    reg.on("before_write", function()
      error("boom")
    end)
    reg.on("before_write", function()
      ran[#ran + 1] = "after the thrower"
    end)
    local proceed, errs = reg.run("before_write", {})
    eq(proceed, true, "a throwing hook does not veto")
    eq(errs, 1, "the throwing hook is counted")
    eq(#ran, 1, "the hook after the thrower runs")
    ok(
      errors[1] and errors[1]:find("before_write:", 1, true) and errors[1]:find("boom", 1, true),
      "on_error gets event and error"
    )

    -- a throwing on_error handler does not break the run either
    local reg2 = hooks.new({
      events = { "before_apply" },
      on_error = function()
        error("handler broke")
      end,
    })
    reg2.on("before_apply", function()
      error("x")
    end)
    local fine, perr = pcall(reg2.run, "before_apply", {})
    ok(fine, "a throwing on_error does not escape: " .. tostring(perr))
  end

  -- Default error reporting goes through vim.notify at WARN.
  do
    local reg = hooks.new({ events = { "before_apply" } })
    reg.on("before_apply", function()
      error("visible")
    end)
    local msg, level
    H.with_patched(vim, "notify", function(m, l)
      msg, level = m, l
    end, function()
      reg.run("before_apply", {})
    end)
    ok(
      msg and msg:find("visible", 1, true) and msg:find("before_apply", 1, true),
      "default on_error notifies with event and error"
    )
    eq(level, vim.log.levels.WARN, "default on_error uses WARN")
  end

  -- Unregister: the returned function, off(), clear(), count().
  do
    local reg = new()
    local n = 0
    local function f()
      n = n + 1
    end
    local off1 = reg.on("after_apply", f)
    reg.on("after_apply", f)
    eq(reg.count("after_apply"), 2, "count")
    off1()
    off1() -- safe twice
    eq(
      reg.count("after_apply"),
      1,
      "the returned function unregisters exactly its own registration"
    )
    eq(reg.off("after_apply", f), true, "off removes a hook")
    eq(reg.off("after_apply", f), false, "off of a missing hook reports false")
    reg.on("after_apply", f)
    reg.on("before_apply", f)
    reg.clear("after_apply")
    eq(reg.count("after_apply"), 0, "clear(event)")
    eq(reg.count("before_apply"), 1, "clear(event) leaves other events")
    reg.clear()
    eq(reg.count("before_apply"), 0, "clear() empties every event")
  end

  -- A hook that registers or removes hooks does not change the running pass.
  do
    local reg = new()
    local seen = {}
    reg.on("after_apply", function()
      seen[#seen + 1] = "one"
      reg.on("after_apply", function()
        seen[#seen + 1] = "added"
      end)
    end)
    reg.run("after_apply", {})
    eq(table.concat(seen, ","), "one", "hooks registered during a run wait for the next run")
  end

  -- A typo in the plugin's config hooks is reported, not silently dropped; a bad priority is refused.
  do
    local reg = new()
    local ran = {}
    local proceed, errs = reg.run("before_apply", {}, {
      function()
        ran[#ran + 1] = "fn"
      end,
      "not a function",
    })
    eq(errs, 1, "a non-callable extra entry is counted as an error")
    eq(proceed, true, "... and does not veto")
    eq(#ran, 1, "... and the callable one still ran")
    ok(errors[1] and errors[1]:find("before_apply:", 1, true), "... and is passed to on_error")
    local _, errs2 = reg.run("before_apply", {}, 42)
    eq(errs2, 1, "a non-callable single extra is an error too")
    eq(
      pcall(reg.on, "after_apply", function() end, { priority = "high" }),
      false,
      "on: a non-numeric priority is refused"
    )
  end

  -- Registries are independent; unknown events and bad arguments are errors.
  do
    local a, b = new(), new()
    a.on("after_apply", function() end)
    eq(b.count("after_apply"), 0, "two registries do not share hooks")

    local reg = new()
    eq(pcall(reg.on, "nope", function() end), false, "on: unknown event")
    eq(pcall(reg.run, "nope", {}), false, "run: unknown event")
    eq(pcall(reg.count, "nope"), false, "count: unknown event")
    eq(pcall(reg.clear, "nope"), false, "clear: unknown event")
    eq(pcall(reg.off, "nope", function() end), false, "off: unknown event")
    eq(pcall(reg.on, "after_apply", "not a function"), false, "on: a hook must be a function")
    eq(pcall(hooks.new, {}), false, "new: events are required")
    eq(pcall(hooks.new, { events = {} }), false, "new: events must not be empty")
    eq(
      pcall(hooks.new, { events = { "a" }, vetoable = { "b" } }),
      false,
      "new: vetoable must be a known event"
    )
  end
end
