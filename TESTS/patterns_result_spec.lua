-- TESTS/patterns_result_spec.lua — lib.lua.patterns.result
return function(H)
  local eq, ok = H.eq, H.ok
  local result = require("lib.lua.patterns.result")

  local good, bad = result.ok(2), result.err("boom")
  ok(good.ok and not bad.ok, "ok/err flags")
  ok(
    result.is_result(good) and not result.is_result({ ok = true }),
    "is_result only accepts real results"
  )

  eq(
    good:map(function(v)
      return v * 3
    end).value,
    6,
    "map: applies to ok"
  )
  eq(
    bad:map(function()
      error("must not run")
    end).err,
    "boom",
    "map: error passes through"
  )
  local thrown = good:map(function()
    error("x", 0)
  end)
  ok(not thrown.ok and thrown.err == "x", "map: a throw becomes an error result")

  eq(
    bad:map_err(function(e)
      return e .. "!"
    end).err,
    "boom!",
    "map_err: transforms the error"
  )
  eq(
    good:map_err(function()
      error("must not run")
    end).value,
    2,
    "map_err: ok passes through"
  )

  eq(
    good:and_then(function(v)
      return result.ok(v + 1)
    end).value,
    3,
    "and_then: chains"
  )
  local wrong = good:and_then(function()
    return 5
  end)
  ok(not wrong.ok, "and_then: a non-result return is an error")
  eq(
    bad:and_then(function()
      error("must not run")
    end).err,
    "boom",
    "and_then: error short-circuits"
  )

  eq(good:unwrap_or(0), 2, "unwrap_or: ok value")
  eq(bad:unwrap_or(0), 0, "unwrap_or: default on error")
  eq(good:unwrap(), 2, "unwrap: ok value")
  ok(not pcall(bad.unwrap, bad), "unwrap: raises on error")

  local v, e = bad:to_pair()
  ok(v == nil and e == "boom", "to_pair: nil, err")
  v, e = good:to_pair()
  ok(v == 2 and e == nil, "to_pair: value, nil")

  eq(result.from_pair("a", nil).value, "a", "from_pair: value")
  eq(result.from_pair(nil, "bad").err, "bad", "from_pair: error")
  eq(
    result.from_pcall(function(a)
      return a
    end, 7).value,
    7,
    "from_pcall: ok"
  )
  ok(not result.from_pcall(function()
    error("t", 0)
  end).ok, "from_pcall: throw")
end
