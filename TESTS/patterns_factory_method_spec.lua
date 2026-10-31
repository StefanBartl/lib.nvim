-- TESTS/patterns_factory_method_spec.lua — lib.lua.patterns.factory_method
return function(H)
  local eq, ok = H.eq, H.ok
  local factory_method = require("lib.lua.patterns.factory_method")

  local make = factory_method.new({
    pdf = function(path)
      return { kind = "pdf", path = path }
    end,
    md = function(path)
      return { kind = "md", path = path }
    end,
  })
  eq(make:create("pdf", "a.pdf").path, "a.pdf", "args are passed to the constructor")
  eq(make:create("md", "x").kind, "md", "picks the constructor by kind")
  ok(not pcall(make.create, make, "zip"), "unknown kind raises without a default")

  eq(table.concat(make:kinds(), ","), "md,pdf", "kinds are listed sorted at construction")
  make:register("png", function()
    return { kind = "png" }
  end)
  eq(make:create("png").kind, "png", "register adds a kind")
  eq(table.concat(make:kinds(), ","), "md,pdf,png", "later kinds follow in registration order")
  local before = make:kinds()
  before[1] = "mutated"
  eq(make:kinds()[1], "md", "kinds returns a copy")

  local withdef = factory_method.new({}, {
    default = function(x)
      return { kind = "raw", x = x }
    end,
  })
  eq(withdef:create("anything", 5).kind, "raw", "default handles unknown kinds")
  ok(not pcall(make.register, make, "bad", "nope"), "register rejects a non-function")
end
