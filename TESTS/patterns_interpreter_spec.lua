-- TESTS/patterns_interpreter_spec.lua — lib.lua.patterns.interpreter
return function(H)
  local eq, ok = H.eq, H.ok
  local interpreter = require("lib.lua.patterns.interpreter")

  local eval = interpreter.new({
    num = function(n)
      return n.value
    end,
    add = function(n, ev, env)
      return ev(n.left, env) + ev(n.right, env)
    end,
    mul = function(n, ev, env)
      return ev(n.left, env) * ev(n.right, env)
    end,
    var = function(n, _, env)
      return env[n.name]
    end,
  })

  local function num(v)
    return { type = "num", value = v }
  end
  eq(eval(num(5)), 5, "leaf")
  eq(eval({ type = "add", left = num(1), right = num(2) }), 3, "binary node")
  eq(
    eval({ type = "mul", left = { type = "add", left = num(1), right = num(2) }, right = num(4) }),
    12,
    "nested nodes"
  )
  eq(eval({ type = "var", name = "x" }, { x = 41 }), 41, "environment is passed down")
  eq(
    eval({ type = "add", left = { type = "var", name = "x" }, right = num(1) }, { x = 41 }),
    42,
    "environment reaches children"
  )

  local good, err = pcall(eval, { type = "pow" })
  ok(not good and tostring(err):find("pow", 1, true), "unknown node type raises with its name")
  ok(not pcall(eval, 5), "a non-table node raises")
  ok(not pcall(eval, {}), "a node without type raises")
end
