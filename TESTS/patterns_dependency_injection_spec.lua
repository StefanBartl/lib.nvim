-- TESTS/patterns_dependency_injection_spec.lua — lib.lua.patterns.dependency_injection
return function(H)
  local eq, ok = H.eq, H.ok
  local di = require("lib.lua.patterns.dependency_injection")

  local c = di.new()
  local built = 0
  c:value("config", { root = "." })
  c:provide("scanner", function(k)
    built = built + 1
    return { root = k:resolve("config").root }
  end)

  eq(built, 0, "nothing built up front")
  local s1, s2 = c:resolve("scanner"), c:resolve("scanner")
  ok(s1 == s2 and built == 1, "default is a cached singleton")
  eq(s1.root, ".", "factory resolves other names")

  local n = 0
  c:provide("ticket", function()
    n = n + 1
    return { n = n }
  end, { transient = true })
  ok(c:resolve("ticket") ~= c:resolve("ticket"), "transient builds every time")

  ok(c:has("config") and not c:has("nope"), "has")
  ok(not pcall(c.resolve, c, "nope"), "unknown name raises")

  local child = c:child()
  child:value("config", { root = "/tmp" })
  eq(child:resolve("config").root, "/tmp", "the child overrides a value")
  eq(c:resolve("config").root, ".", "the parent is unchanged")
  ok(child:has("scanner"), "the child sees the parent's entries")
  ok(child:resolve("scanner") == s1, "and shares its cached instances")
  child:provide("scanner", function(k)
    return { root = k:resolve("config").root, fake = true }
  end)
  ok(
    child:resolve("scanner").fake and child:resolve("scanner").root == "/tmp",
    "a child can replace a provider"
  )

  local cyc = di.new()
  cyc:provide("a", function(k)
    return k:resolve("b")
  end)
  cyc:provide("b", function(k)
    return k:resolve("a")
  end)
  local good, err = pcall(cyc.resolve, cyc, "a")
  ok(not good and tostring(err):find("cycle", 1, true), "cycles are detected")
  local again = pcall(cyc.resolve, cyc, "a")
  ok(not again, "and detected again (state was cleaned up)")

  local fail = di.new()
  fail:provide("x", function()
    error("cannot build", 0)
  end)
  ok(not pcall(fail.resolve, fail, "x"), "a failing factory raises")
  ok(not pcall(fail.resolve, fail, "x"), "and is retried (no half-built cache)")
  ok(not pcall(fail.provide, fail, "y", 5), "factory must be a function")
end
