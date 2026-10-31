-- TESTS/patterns_template_method_spec.lua — lib.lua.patterns.template_method
return function(H)
  local eq, ok = H.eq, H.ok
  local template_method = require("lib.lua.patterns.template_method")

  local order = {}
  local import = template_method.define({
    steps = {
      read = { required = true },
      parse = { required = true },
      validate = {
        default = function(data)
          order[#order + 1] = "default-validate"
          return data
        end,
      },
    },
    run = function(step, source)
      order[#order + 1] = "start"
      return step.validate(step.parse(step.read(source)))
    end,
  })

  local run = import.implement({
    read = function(s)
      order[#order + 1] = "read"
      return "raw:" .. s
    end,
    parse = function(raw)
      order[#order + 1] = "parse"
      return raw:upper()
    end,
  })
  eq(run("x"), "RAW:X", "skeleton runs the steps")
  eq(
    table.concat(order, ","),
    "start,read,parse,default-validate",
    "skeleton order, default step used"
  )

  order = {}
  local strict = import.implement({
    read = function(s)
      return s
    end,
    parse = function(s)
      return s
    end,
    validate = function(d)
      order[#order + 1] = "own-validate"
      return d
    end,
  })
  strict("q")
  eq(order[#order], "own-validate", "an own step replaces the default")

  ok(
    not pcall(import.implement, { read = function() end }),
    "missing required step raises at implement()"
  )
  ok(
    not pcall(
      import.implement,
      { read = function() end, parse = function() end, extra = function() end }
    ),
    "unknown step raises"
  )
  ok(not pcall(import.implement, { read = 5, parse = function() end }), "step must be a function")
  ok(not pcall(template_method.define, { steps = {} }), "define needs run")

  local a = import.implement({
    read = function()
      return "1"
    end,
    parse = function(x)
      return x
    end,
  })
  local b = import.implement({
    read = function()
      return "2"
    end,
    parse = function(x)
      return x
    end,
  })
  ok(a() == "1" and b() == "2", "implementations are independent")
end
