-- TESTS/patterns_flyweight_spec.lua — lib.lua.patterns.flyweight
return function(H)
  local eq, ok = H.eq, H.ok
  local flyweight = require("lib.lua.patterns.flyweight")

  local made = 0
  local hl = flyweight.new(function(fg, bg)
    made = made + 1
    return { fg = fg, bg = bg }
  end)

  local a = hl:get("red", "black")
  local b = hl:get("red", "black")
  ok(a == b, "equal keys share one instance")
  eq(made, 1, "factory ran once")
  ok(hl:get("red", "white") ~= a, "different keys give different instances")
  eq(hl:size(), 2, "size counts cached instances")

  -- separator keeps ("a","bc") and ("ab","c") apart
  local pair = flyweight.new(function(x, y)
    return { x, y }
  end)
  ok(pair:get("a", "bc") ~= pair:get("ab", "c"), "key parts do not run together")

  local custom = flyweight.new(function(t)
    return { name = t.name }
  end, {
    key = function(t)
      return t.name
    end,
  })
  ok(custom:get({ name = "n" }) == custom:get({ name = "n" }), "custom key function")

  hl:clear()
  eq(hl:size(), 0, "clear empties the cache")
  ok(hl:get("red", "black") ~= a, "after clear a new instance is made")

  local weak = flyweight.new(function()
    return {}
  end, { weak = true })
  weak:get("k")
  collectgarbage()
  collectgarbage()
  eq(weak:size(), 0, "weak cache lets unused instances go")
end
