-- TESTS/patterns_adapter_spec.lua — lib.lua.patterns.adapter
return function(H)
  local eq, ok = H.eq, H.ok
  local adapter = require("lib.lua.patterns.adapter")

  local log = {}
  local foreign = {
    reload = function()
      log[#log + 1] = "reload"
      return "reloaded"
    end,
    get_node_path = function(x)
      return "/p/" .. tostring(x)
    end,
    same = function()
      return "same"
    end,
  }

  local explorer = adapter.new({ "refresh", "current_path", "same" }, foreign, {
    refresh = function(adaptee)
      return adaptee.reload()
    end,
    current_path = "get_node_path",
  })

  eq(explorer.refresh(), "reloaded", "function mapping receives the adaptee")
  eq(explorer.current_path(7), "/p/7", "name mapping forwards the arguments")
  eq(explorer.same(), "same", "unmapped name falls back to the same-named function")
  eq(#log, 1, "adaptee was called once")

  local extra = false
  for k in pairs(explorer) do
    if k ~= "refresh" and k ~= "current_path" and k ~= "same" then
      extra = true
    end
  end
  ok(not extra, "only the interface methods are exposed")

  ok(
    not pcall(adapter.new, { "missing" }, foreign),
    "an unprovidable method raises at construction"
  )
  ok(
    not pcall(adapter.new, { "x" }, foreign, { x = "nope" }),
    "a mapped name that does not exist raises at construction"
  )
end
