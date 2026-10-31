-- TESTS/patterns_mediator_spec.lua — lib.lua.patterns.mediator
return function(H)
  local eq, ok = H.eq, H.ok
  local mediator = require("lib.lua.patterns.mediator")

  local log = {}
  local function comp(name, result)
    return {
      handle = function(from, msg, ...)
        log[#log + 1] = ("%s<-%s:%s:%s"):format(
          name,
          from,
          tostring(msg),
          table.concat({ ... }, "+")
        )
        return result
      end,
    }
  end

  local m = mediator.new()
  m:register("tree", comp("tree", "t")):register("preview", comp("preview", "p"))

  eq(m:send("tree", "preview", "show", "a.md", "x"), "p", "send returns the target's result")
  eq(log[1], "preview<-tree:show:a.md+x", "send passes sender, message and arguments")
  ok(not pcall(m.send, m, "tree", "nobody", "hi"), "unknown target raises")

  log = {}
  m:register("status", comp("status", "s"))
  local reached = m:broadcast("tree", "closed")
  eq(reached, 2, "broadcast reaches everyone but the sender")
  eq(table.concat(log, "|"), "preview<-tree:closed:|status<-tree:closed:", "in registration order")

  m:register("bad", {
    handle = function()
      error("kaput", 0)
    end,
  })
  local r, errs = m:broadcast("tree", "x")
  eq(r, 3, "a raising component is still counted")
  eq(errs[1], "kaput", "its error is returned, the others ran")

  ok(m:unregister("bad") and not m:unregister("bad"), "unregister")
  eq(table.concat(m:names(), ","), "tree,preview,status", "names")
  m:register("tree", comp("tree2", "t2"))
  eq(#m:names(), 3, "re-registering a name replaces it in place")
  eq(m:send("x", "tree", "m"), "t2", "the replacement answers")
  ok(not pcall(m.register, m, "bad", {}), "component needs handle")
end
