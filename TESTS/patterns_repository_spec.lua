-- TESTS/patterns_repository_spec.lua — lib.lua.patterns.repository
return function(H)
  local eq, ok = H.eq, H.ok
  local repository = require("lib.lua.patterns.repository")

  local users = repository.new(repository.memory())
  eq(users:count(), 0, "empty")
  users:save("u1", { name = "Ada", age = 36 })
  users:save("u2", { name = "Bob", age = 20 })
  users:save("u3", { name = "Cy", age = 36 })
  eq(users:count(), 3, "count")
  eq(users:get("u2").name, "Bob", "get")
  eq(users:get("nope"), nil, "get of an unknown id")

  users:save("u2", { name = "Bobby", age = 21 })
  eq(users:count(), 3, "save of an existing id replaces")
  eq(users:get("u2").name, "Bobby", "replaced value")

  local found = users:find(function(u)
    return u.age == 36
  end)
  ok(
    found.id == "u1" and found.value.name == "Ada",
    "find returns the first match in insertion order"
  )
  eq(
    users:find(function(u)
      return u.age == 99
    end),
    nil,
    "find without a match"
  )
  local all36 = users:filter(function(u)
    return u.age == 36
  end)
  eq(#all36, 2, "filter returns every match")
  eq(all36[2].id, "u3", "filter keeps order")

  local seen_id
  users:find(function(_, id)
    seen_id = id
    return true
  end)
  eq(seen_id, "u1", "the predicate also gets the id")

  users:remove("u1")
  eq(users:count(), 2, "remove")
  eq(users:all()[1].id, "u2", "order after removal")
  users:remove("u1")
  eq(users:count(), 2, "removing twice is harmless")

  ok(not pcall(users.save, users, "x", nil), "saving nil raises")
  ok(not pcall(repository.new, { get = function() end }), "a store must have all primitives")

  -- any table with the four primitives works as a store
  local log = {}
  local custom = repository.new({
    get = function() end,
    put = function(id)
      log[#log + 1] = id
    end,
    delete = function() end,
    all = function()
      return {}
    end,
  })
  custom:save("k", 1)
  eq(log[1], "k", "a custom store receives the writes")
end
