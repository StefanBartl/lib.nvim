-- TESTS/patterns_singleton_spec.lua — lib.lua.patterns.singleton
return function(H)
  local eq, ok = H.eq, H.ok
  local singleton = require("lib.lua.patterns.singleton")

  local made = 0
  local s = singleton.new(function()
    made = made + 1
    return { id = made }
  end)

  eq(s:is_created(), false, "nothing is created up front")
  eq(made, 0, "factory not called yet")
  local a, b = s:get(), s:get()
  ok(a == b, "same instance every time")
  eq(made, 1, "factory ran once")
  eq(s:is_created(), true, "is_created after get")

  s:reset()
  eq(s:is_created(), false, "reset forgets the instance")
  eq(s:get().id, 2, "next get creates again")

  local failing = singleton.new(function()
    error("no luck", 0)
  end)
  local good, err = pcall(failing.get, failing)
  ok(not good and err == "no luck", "a failing factory raises its error")
  ok(not failing:is_created(), "a failed creation is not remembered")
  ok(not pcall(failing.get, failing), "the next get tries again")

  local re
  re = singleton.new(function()
    return re:get()
  end)
  ok(not pcall(re.get, re), "a re-entrant factory is detected")
  ok(not pcall(singleton.new, nil), "factory is required")
end
