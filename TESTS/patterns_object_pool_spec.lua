-- TESTS/patterns_object_pool_spec.lua — lib.lua.patterns.object_pool
return function(H)
  local eq, ok = H.eq, H.ok
  local object_pool = require("lib.lua.patterns.object_pool")

  local destroyed = 0
  local pool = object_pool.new({
    create = function()
      return { dirty = false }
    end,
    reset = function(o)
      o.dirty = false
    end,
    destroy = function()
      destroyed = destroyed + 1
    end,
    max = 1,
  })

  local a = pool:acquire()
  a.dirty = true
  pool:release(a)
  eq(pool:stats().idle, 1, "release keeps the object")
  local b = pool:acquire()
  ok(a == b and not b.dirty, "acquire reuses and the object was reset")
  eq(pool:stats().reused, 1, "reuse counted")

  local c = pool:acquire()
  pool:release(b)
  pool:release(c)
  eq(pool:stats().idle, 1, "max idle respected")
  eq(destroyed, 1, "overflow object destroyed")

  local seen
  eq(
    pool:with(function(o)
      seen = o
      return "r"
    end),
    "r",
    "with returns the callback result"
  )
  eq(pool:stats().idle, 1, "with releases")

  local err_ok, err = pcall(pool.with, pool, function()
    error("kaputt", 0)
  end)
  ok(not err_ok and err == "kaputt", "with re-raises after releasing")
  eq(pool:stats().idle, 1, "with released after a raise too")
  ok(seen ~= nil, "callback got an object")

  pool:clear()
  eq(pool:stats().idle, 0, "clear empties")
  eq(destroyed, 2, "clear destroys idle objects")

  local bad = object_pool.new({
    create = function()
      return {}
    end,
    reset = function()
      error("no reset")
    end,
    destroy = function()
      destroyed = destroyed + 1
    end,
  })
  bad:release(bad:acquire())
  eq(bad:stats().idle, 0, "an object whose reset raises is dropped")
  ok(not pcall(object_pool.new, {}), "create is required")
end
