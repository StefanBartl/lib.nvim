-- TESTS/scoring_spec.lua — lib.lua.scoring: base + named bonus/malus list, clamp, details, rounding.

return function(H)
  local eq, ok = H.eq, H.ok
  local scoring = require("lib.lua.scoring")

  -- base only
  local r = scoring.new({ base = 40 }):result()
  eq(r.score, 40, "base only: the score is the base")
  eq(r.raw, 40, "base only: raw")
  eq(#r.details, 0, "base only: no details")
  eq(scoring.new():result().score, 0, "no options: base 0")

  -- additive, with the breakdown
  local s = scoring.new({ base = 50 })
  s:bonus("fast", 20):malus("typos", 7):bonus("streak", 5)
  r = s:result()
  eq(r.score, 68, "additive: 50 + 20 - 7 + 5")
  eq(#r.details, 3, "details: one entry per contribution")
  eq(r.details[1].name, "fast", "details: in the order added")
  eq(r.details[1].delta, 20, "details: the signed contribution")
  eq(r.details[1].total, 70, "details: the running total")
  eq(r.details[2].delta, -7, "details: a malus is negative")
  eq(r.details[2].total, 63, "details: ... and lowers the running total")
  eq(r.details[3].total, 68, "details: the last total is the raw score")

  -- malus takes the magnitude whichever sign was passed
  r = scoring.new():malus("a", 5):malus("b", -5):result()
  eq(r.score, -10, "malus: the sign passed does not matter")

  -- `applies = false` leaves a contribution out entirely
  r = scoring
    .new({ base = 10 })
    :bonus("yes", 5, true)
    :bonus("no", 100, false)
    :malus("no2", 3, false)
    :result()
  eq(r.score, 15, "applies=false: not counted")
  eq(#r.details, 1, "applies=false: not listed either")

  -- clamp, and which bound cut
  r = scoring.new({ base = 90, min = 0, max = 100 }):bonus("x", 30):result()
  eq(r.score, 100, "clamp: cut at max")
  eq(r.raw, 120, "clamp: raw keeps the unclamped value")
  eq(r.clamped, "max", "clamp: reports max")
  r = scoring.new({ base = 5, min = 0, max = 100 }):malus("x", 30):result()
  eq(r.score, 0, "clamp: cut at min")
  eq(r.clamped, "min", "clamp: reports min")
  r = scoring.new({ base = 5, min = 0, max = 100 }):bonus("x", 10):result()
  eq(r.clamped, nil, "clamp: nil when nothing was cut")
  r = scoring.new({ min = 0 }):bonus("x", 1e9):result()
  eq(r.score, 1e9, "clamp: a missing bound does not cut")
  r = scoring.new({ min = 10, max = 10 }):bonus("x", 99):result()
  eq(r.score, 10, "clamp: min == max pins the score")

  -- rounding happens after the clamp
  eq(scoring.compute({ { name = "a", delta = 2.5 } }, { round = "floor" }).score, 2, "round floor")
  eq(scoring.compute({ { name = "a", delta = 2.2 } }, { round = "ceil" }).score, 3, "round ceil")
  eq(
    scoring.compute({ { name = "a", delta = 2.5 } }, { round = "nearest" }).score,
    3,
    "round nearest"
  )
  eq(
    scoring.compute({ { name = "a", delta = 10.4 } }, { max = 10.2, round = "nearest" }).score,
    10,
    "round: after the clamp"
  )

  -- the builder can be read more than once and keeps collecting
  local b = scoring.new({ base = 1 })
  b:bonus("a", 1)
  eq(b:result().score, 2, "builder: first read")
  b:bonus("b", 1)
  eq(b:result().score, 3, "builder: collects after a read")

  -- compute is the same without the builder
  r = scoring.compute(
    { { name = "a", delta = 3 }, { name = "b", delta = -1, applies = true } },
    { base = 1 }
  )
  eq(r.score, 3, "compute: entries list")

  -- invalid input is an error naming the problem
  local function fails(fn, what)
    local good, err = pcall(fn)
    eq(good, false, what)
    ok(
      type(err) == "string" and err:find("lib.lua.scoring", 1, true) ~= nil,
      what .. " (message names the module)"
    )
  end
  fails(function()
    scoring.new({ base = 0 / 0 })
  end, "NaN base")
  fails(function()
    scoring.new({ min = 5, max = 1 })
  end, "min > max")
  fails(function()
    scoring.new({ round = "up" })
  end, "unknown rounding")
  fails(function()
    scoring.new():bonus("x", math.huge)
  end, "infinite delta is refused where it is passed, not at result()")
  -- the error names the line of the caller, also through bonus()/malus() (they must stay tail calls)
  local function located(f)
    local _, msg = pcall(f)
    return tostring(msg):match("scoring_spec%.lua:%d+") ~= nil
  end
  ok(
    located(function()
      scoring.new():bonus("x", 0 / 0)
    end),
    "bonus: error located at the caller"
  )
  ok(
    located(function()
      scoring.new():malus("x", nil)
    end),
    "malus: error located at the caller"
  )
  ok(
    located(function()
      scoring.new():add("x", 0 / 0)
    end),
    "add: error located at the caller"
  )
  ok(
    located(function()
      scoring.compute({ { name = "x", delta = 0 / 0 } })
    end),
    "compute: bad delta located at the caller"
  )
  ok(
    located(function()
      scoring.compute({ { name = "", delta = 1 } })
    end),
    "compute: empty name located at the caller"
  )
  fails(function()
    scoring.compute({ "not a table" })
  end, "compute: non-table entry")
  -- a number or boolean entry cannot be indexed: only the explicit guard names the module and the cause
  for _, bad in ipairs({ 5, true }) do
    local good, err = pcall(scoring.compute, { bad })
    eq(good, false, "compute: non-table entry (" .. type(bad) .. ")")
    ok(
      type(err) == "string"
        and err:find("lib.lua.scoring.compute: entries[1] must be a table", 1, true) ~= nil,
      "compute: a " .. type(bad) .. " entry says it must be a table"
    )
  end
  fails(function()
    scoring.new():bonus("", 1):result()
  end, "empty name")
  fails(function()
    scoring.compute("nope")
  end, "entries must be a list")
end
