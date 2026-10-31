-- TESTS/patterns_composite_spec.lua — lib.lua.patterns.composite
return function(H)
  local eq, ok = H.eq, H.ok
  local composite = require("lib.lua.patterns.composite")

  local function leaf(name, fail)
    return {
      refresh = function(self, x)
        if fail then
          error(name .. " broke", 0)
        end
        return name .. (x or "")
      end,
    }
  end

  local a, b, c = leaf("a"), leaf("b"), leaf("c")
  local group = composite.new({ a, b })
  local res, errs = group:call("refresh", "!")
  eq(table.concat(res, ","), "a!,b!", "call reaches every child with the arguments")
  eq(#errs, 0, "no errors")

  group:add(composite.new({ c }))
  res = group:call("refresh")
  eq(res[3][1], "c", "a nested group yields a nested list")
  eq(group:size(), 3, "size counts direct children")

  ok(group:remove(b), "remove finds the child")
  ok(not group:remove(b), "removing twice reports false")
  eq(group:size(), 2, "size after remove")

  local mixed = composite.new({ leaf("x", true), leaf("y"), { other = function() end } })
  local r2, e2 = mixed:call("refresh")
  eq(#r2, 1, "a failing child does not stop the others")
  eq(e2[1], "x broke", "its error is returned")

  local none = composite.new({ { other = true } })
  eq(#none:call("refresh"), 0, "children without the method are skipped")

  local source = { a }
  local copy = composite.new(source)
  copy:add(b)
  eq(#source, 1, "the input list is not modified")
  ok(composite.new().items ~= nil, "new() without children works")
end
