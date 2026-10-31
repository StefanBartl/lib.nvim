-- TESTS/patterns_abstract_factory_spec.lua — lib.lua.patterns.abstract_factory
return function(H)
  local eq, ok = H.eq, H.ok
  local abstract_factory = require("lib.lua.patterns.abstract_factory")

  local ui = abstract_factory.new({
    ascii = {
      border = function()
        return "+-+"
      end,
      icon = function(n)
        return "*" .. (n or "")
      end,
    },
    nerd = {
      border = function()
        return "round"
      end,
      icon = function()
        return "N"
      end,
    },
  })

  eq(table.concat(ui:names(), ","), "ascii,nerd", "names sorted")
  eq(ui:create("ascii", "border"), "+-+", "create builds a product")
  eq(ui:create("ascii", "icon", 3), "*3", "args reach the constructor")
  eq(ui:family("nerd").icon(), "N", "family exposes its constructors")

  ok(not pcall(ui.create, ui, "unknown", "icon"), "unknown family raises")
  ok(not pcall(ui.create, ui, "ascii", "tooltip"), "unknown product raises")

  local good = pcall(abstract_factory.new, {
    a = { x = function() end },
    b = { x = function() end, y = function() end },
  })
  ok(not good, "families must provide the same products")
  ok(not pcall(abstract_factory.new, { a = { x = 1 } }), "products must be functions")
end
