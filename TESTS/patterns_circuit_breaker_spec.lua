-- TESTS/patterns_circuit_breaker_spec.lua — lib.lua.patterns.circuit_breaker
return function(H)
  local eq, ok = H.eq, H.ok
  local cb = require("lib.lua.patterns.circuit_breaker")

  local clock = 0
  local changes = {}
  local b = cb.new({
    threshold = 2,
    reset_ms = 100,
    now = function()
      return clock
    end,
    on_change = function(new, old)
      changes[#changes + 1] = old .. ">" .. new
    end,
  })

  local calls = 0
  local function fail()
    calls = calls + 1
    error("down", 0)
  end
  local function good()
    calls = calls + 1
    return "fine"
  end

  eq(b:state(), "closed", "starts closed")
  local okc, v = b:call(good)
  ok(okc and v == "fine", "closed: passes the result through")

  local f1, e1 = b:call(fail)
  ok(not f1 and e1 == "down", "failure returns false, err")
  eq(b:state(), "closed", "below threshold stays closed")
  b:call(fail)
  eq(b:state(), "open", "threshold reached opens")

  calls = 0
  local o, msg = b:call(good)
  ok(not o and msg == "circuit open", "open: rejects without calling")
  eq(calls, 0, "open: the function was not run")

  clock = 100
  eq(b:state(), "half_open", "after the pause: half open")
  b:call(fail)
  eq(b:state(), "open", "failed probe reopens")

  clock = 250
  local pok, pv = b:call(good)
  ok(pok and pv == "fine", "successful probe goes through")
  eq(b:state(), "closed", "successful probe closes")
  eq(
    table.concat(changes, ","),
    "closed>open,open>half_open,half_open>open,open>half_open,half_open>closed",
    "state changes reported"
  )

  b:call(fail)
  b:call(fail)
  eq(b:state(), "open", "opens again")
  b:reset()
  eq(b:state(), "closed", "reset closes")
end
