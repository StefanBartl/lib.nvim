-- TESTS/patterns_strategy_spec.lua — lib.lua.patterns.strategy
return function(H)
  local eq, ok = H.eq, H.ok
  local strategy = require("lib.lua.patterns.strategy")

  local render = strategy.new({
    plain = function(item)
      return item.name
    end,
    long = function(item)
      return item.name .. " (" .. item.path .. ")"
    end,
  }, { default = "plain" })

  local item = { name = "a", path = "/x" }
  eq(render:selected(), "plain", "default is selected")
  eq(render:run(item), "a", "run uses the current strategy")
  render:use("long")
  eq(render:run(item), "a (/x)", "use switches")
  eq(render:call("plain", item), "a", "call runs one strategy once")
  eq(render:selected(), "long", "call leaves the selection alone")
  eq(table.concat(render:names(), ","), "long,plain", "names sorted")

  render:register("upper", function(it)
    return it.name:upper()
  end)
  eq(render:use("upper"):run(item), "A", "register + chained use")

  ok(not pcall(render.use, render, "nope"), "use of an unknown strategy raises")
  ok(not pcall(render.call, render, "nope"), "call of an unknown strategy raises")
  ok(not pcall(render.register, render, "bad", 5), "strategy must be a function")

  local none = strategy.new({ a = function() end })
  ok(not pcall(none.run, none), "run without a selection raises")
  ok(
    not pcall(strategy.new, { a = function() end }, { default = "missing" }),
    "unknown default raises"
  )
end
