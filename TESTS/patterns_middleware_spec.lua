-- TESTS/patterns_middleware_spec.lua — lib.lua.patterns.middleware
return function(H)
  local eq, ok = H.eq, H.ok
  local middleware = require("lib.lua.patterns.middleware")

  local order = {}
  local chain = middleware.new()
  chain
    :use(function(_, next)
      order[#order + 1] = "a-in"
      local r = next()
      order[#order + 1] = "a-out"
      return r
    end)
    :use(function(ctx, next)
      order[#order + 1] = "b-in"
      ctx.seen = true
      return next()
    end)

  local res = chain:run({}, function(ctx)
    order[#order + 1] = "final"
    return ctx.seen and "done" or "no"
  end)
  eq(res, "done", "return value travels back out")
  eq(table.concat(order, ","), "a-in,b-in,final,a-out", "stages nest in order")

  local stopped = middleware.new():use(function()
    return nil, "stopped"
  end)
  local called = false
  local r, err = stopped:run({}, function()
    called = true
  end)
  ok(r == nil and err == "stopped", "a stage that does not call next stops the chain")
  ok(not called, "final does not run after a stop")

  eq(middleware.new():run({}), nil, "empty chain without final returns nothing")
  eq(
    middleware.new():run({ v = 5 }, function(ctx)
      return ctx.v
    end),
    5,
    "empty chain runs final"
  )

  local twice = middleware.new():use(function(_, next)
    next()
    return next()
  end)
  ok(not pcall(twice.run, twice, {}), "calling next twice raises")
  ok(not pcall(chain.use, chain, "nope"), "use rejects a non-function")
end
