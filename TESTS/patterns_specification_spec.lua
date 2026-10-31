-- TESTS/patterns_specification_spec.lua — lib.lua.patterns.specification
return function(H)
  local eq, ok = H.eq, H.ok
  local spec = require("lib.lua.patterns.specification")

  local is_lua = spec.new(function(f)
    return f:match("%.lua$") ~= nil
  end)
  local is_test = spec.new(function(f)
    return f:match("_spec%.lua$") ~= nil
  end)

  eq(is_lua:is_satisfied_by("a.lua"), true, "base: satisfied")
  eq(is_lua:is_satisfied_by("a.txt"), false, "base: not satisfied")
  eq(is_lua("a.lua"), true, "callable form")

  local wanted = is_lua:and_(is_test:not_())
  eq(wanted("a.lua"), true, "and/not: lua but not test")
  eq(wanted("a_spec.lua"), false, "and/not: a test is excluded")
  eq(wanted("a.txt"), false, "and/not: not lua")

  local either = is_test:or_(spec.new(function(f)
    return f == "init.lua"
  end))
  eq(either("init.lua"), true, "or: right side")
  eq(either("x_spec.lua"), true, "or: left side")
  eq(either("x.lua"), false, "or: neither")

  eq(spec.all({})("anything"), true, "all of nothing is satisfied")
  eq(spec.any({})("anything"), false, "any of nothing is not satisfied")
  eq(spec.all({ is_lua, is_test })("a_spec.lua"), true, "all: both")
  eq(spec.all({ is_lua, is_test })("a.lua"), false, "all: one fails")
  eq(spec.any({ is_lua, is_test })("a.lua"), true, "any: one holds")

  local truthy = spec.new(function()
    return "yes"
  end)
  eq(truthy(1), true, "result is coerced to a boolean")
  ok(not pcall(spec.new, "nope"), "new: rejects a non-function")
end
