-- TESTS/patterns_chain_of_responsibility_spec.lua — lib.lua.patterns.chain_of_responsibility
return function(H)
  local eq, ok = H.eq, H.ok
  local cor = require("lib.lua.patterns.chain_of_responsibility")

  local chain = cor.new()
  chain:add("lua", function(path)
    if path:match("%.lua$") then
      return true, "lua"
    end
  end)
  chain:add("md", function(path)
    if path:match("%.md$") then
      return true, "md"
    end
  end)

  local handled, res, name = chain:handle("a.md")
  ok(handled and res == "md" and name == "md", "second handler claims the request")
  handled, res, name = chain:handle("a.lua")
  ok(handled and res == "lua" and name == "lua", "first handler claims the request")
  local none, r2, n2 = chain:handle("a.txt")
  ok(none == false and r2 == nil and n2 == nil, "unclaimed request")

  chain:add("any", function()
    return true, "fallback"
  end)
  eq(select(2, chain:handle("a.txt")), "fallback", "a later catch-all handles the rest")
  chain:add("first", function()
    return true, "front"
  end, { first = true })
  eq(select(2, chain:handle("a.lua")), "front", "first = true goes to the front")
  eq(table.concat(chain:names(), ","), "first,lua,md,any", "order")

  chain:add("md", function()
    return true, "replaced"
  end)
  eq(
    table.concat(chain:names(), ","),
    "first,lua,any,md",
    "same name replaces and moves to the end"
  )
  ok(chain:remove("first") and not chain:remove("first"), "remove")

  local c2 = cor.new()
  c2:add("bad", function()
    error("boom", 0)
  end)
  c2:add("good", function()
    return true, "ok"
  end)
  local h, v, nm, errs = c2:handle("x")
  ok(h and v == "ok" and nm == "good", "a raising handler does not stop the chain")
  eq(errs[1], "boom", "its error is collected")
  local h2, _, _, errs2 = cor
    .new()
    :add("only", function()
      error("x", 0)
    end)
    :handle("y")
  ok(not h2 and #errs2 == 1, "all handlers failing: not handled, errors returned")
  ok(not pcall(chain.add, chain, "bad", 5), "handler must be a function")

  local seen
  cor
    .new()
    :add("args", function(req, a, b)
      seen = { req, a, b }
      return true
    end)
    :handle("r", 1, 2)
  ok(seen[1] == "r" and seen[2] == 1 and seen[3] == 2, "extra arguments are passed on")
end
