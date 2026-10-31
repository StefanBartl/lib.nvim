-- TESTS/patterns_event_bus_spec.lua — lib.lua.patterns.event_bus
return function(H)
  local eq, ok = H.eq, H.ok
  local event_bus = require("lib.lua.patterns.event_bus")

  local bus = event_bus.new()
  local got = {}
  local off = bus:on("saved", function(path, n)
    got[#got + 1] = path .. ":" .. n
  end)
  bus:on("saved", function()
    error("listener failed", 0)
  end)
  bus:on("saved", function(path)
    got[#got + 1] = "third:" .. path
  end)

  local called, errors = bus:emit("saved", "a.lua", 1)
  eq(called, 3, "all listeners called")
  eq(#errors, 1, "failure collected")
  eq(errors[1], "listener failed", "failure text")
  eq(table.concat(got, ","), "a.lua:1,third:a.lua", "a failing listener does not stop the others")

  off()
  eq(bus:count("saved"), 2, "unsubscribe removes the listener")
  off()
  eq(bus:count("saved"), 2, "unsubscribe twice is harmless")

  local once = 0
  bus:once("tick", function()
    once = once + 1
  end)
  bus:emit("tick")
  bus:emit("tick")
  eq(once, 1, "once fires once")

  local wild = {}
  bus:on("*", function(topic, x)
    wild[#wild + 1] = topic .. "=" .. tostring(x)
  end)
  bus:emit("alpha", 1)
  bus:emit("beta", 2)
  eq(table.concat(wild, ","), "alpha=1,beta=2", "wildcard receives topic first")

  local self_off
  local runs = 0
  self_off = bus:on("self", function()
    runs = runs + 1
    self_off()
  end)
  bus:on("self", function()
    runs = runs + 10
  end)
  bus:emit("self")
  eq(runs, 11, "unsubscribing during emit does not skip the next listener")

  eq(
    select(1, bus:emit("nobody")),
    1,
    "only the wildcard listener is called for an unsubscribed topic"
  )
  bus:clear("saved")
  eq(bus:count("saved"), 0, "clear topic")
  bus:clear()
  ok(bus:count("alpha") == 0 and bus:count("*") == 0, "clear all")
end
