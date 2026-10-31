-- TESTS/patterns_state_machine_spec.lua — lib.lua.patterns.state_machine
return function(H)
  local eq, ok = H.eq, H.ok
  local state_machine = require("lib.lua.patterns.state_machine")

  local log = {}
  local ctx = { locked = false }
  local sm = state_machine.new({
    initial = "idle",
    ctx = ctx,
    transitions = {
      {
        from = "idle",
        event = "start",
        to = "running",
        action = function(_, from, to, x)
          log[#log + 1] = "action:" .. from .. ">" .. to .. ":" .. tostring(x)
        end,
      },
      {
        from = "running",
        event = "stop",
        to = "idle",
        guard = function(c)
          return not c.locked
        end,
      },
      { from = "*", event = "reset", to = "idle" },
    },
    on_enter = {
      running = function(from)
        log[#log + 1] = "enter:running<" .. from
      end,
    },
    on_exit = {
      idle = function(to)
        log[#log + 1] = "exit:idle>" .. to
      end,
    },
  })

  eq(sm:state(), "idle", "initial state")
  ok(sm:is("idle") and sm:can("start") and not sm:can("stop"), "can/is")

  local changes = {}
  local off = sm:on_change(function(new, old, event)
    changes[#changes + 1] = old .. ">" .. new .. "@" .. event
  end)

  local fired, to = sm:fire("start", 42)
  ok(fired and to == "running", "fire returns new state")
  eq(
    table.concat(log, "|"),
    "exit:idle>running|action:idle>running:42|enter:running<idle",
    "hook order: exit, action, enter"
  )

  ctx.locked = true
  local f2, why = sm:fire("stop")
  ok(not f2 and why == "guard rejected", "guard rejects")
  eq(sm:state(), "running", "state unchanged after a rejection")
  ctx.locked = false

  local f3, why3 = sm:fire("start")
  ok(not f3 and why3:find("not allowed", 1, true), "event not allowed in this state")
  local f4, why4 = sm:fire("nope")
  ok(not f4 and why4:find("unknown event", 1, true), "unknown event")

  ok(sm:fire("stop"), "stop works when unlocked")
  sm:fire("start")
  ok(sm:fire("reset"), "wildcard from")
  eq(sm:state(), "idle", "wildcard target")

  off()
  sm:fire("start")
  eq(#changes, 4, "listener saw changes until unsubscribed")

  ok(
    not pcall(state_machine.new, { initial = "a", on_enter = { b = function() end } }),
    "unknown state in on_enter is rejected"
  )
  ok(not pcall(state_machine.new, {}), "initial is required")

  -- several guarded transitions for one event: the first whose guard passes wins
  local multi = state_machine.new({
    initial = "idle",
    ctx = { big = true },
    transitions = {
      {
        from = "idle",
        event = "go",
        to = "small",
        guard = function(c)
          return not c.big
        end,
      },
      {
        from = "idle",
        event = "go",
        to = "large",
        guard = function(c)
          return c.big
        end,
      },
    },
  })
  local mok, mto = multi:fire("go")
  ok(mok and mto == "large", "a rejected guard does not hide a later matching transition")
end
