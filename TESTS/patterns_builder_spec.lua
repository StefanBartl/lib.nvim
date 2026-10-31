-- TESTS/patterns_builder_spec.lua — lib.lua.patterns.builder
return function(H)
  local eq, ok = H.eq, H.ok
  local builder = require("lib.lua.patterns.builder")

  local new_cmd = builder.new({
    name = { required = true },
    nargs = {
      default = 0,
      validate = function(v)
        return type(v) == "number"
      end,
    },
    desc = {},
  })

  local cmd, err = new_cmd():name("Foo"):nargs(2):build()
  ok(cmd and err == nil, "build succeeds")
  eq(cmd.name, "Foo", "fluent setter stores the value")
  eq(cmd.nargs, 2, "second setter")
  eq(cmd.desc, nil, "unset optional field stays nil")

  local d = new_cmd():set("name", "X"):build()
  eq(d.nargs, 0, "default applies")

  local missing, merr = new_cmd():build()
  ok(missing == nil and merr:find("name", 1, true), "required field missing is reported")

  local bad, berr = new_cmd():name("X"):nargs("two"):build()
  ok(bad == nil and berr:find("nargs", 1, true), "validator rejects")

  ok(not pcall(function()
    new_cmd():set("nope", 1)
  end), "unknown field raises")
  ok(not pcall(builder.new, { build = {} }), "reserved field name raises")

  local a, b = new_cmd(), new_cmd()
  a:name("A")
  eq(b:get("name"), nil, "builders do not share state")
  eq(a:get("nargs"), 0, "get falls back to the default")
end
