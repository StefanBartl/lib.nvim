-- TESTS/registry_spec.lua — lib.nvim.registry: ordered key -> value registry with a lazy loader,
-- validation, duplicate policy and reset().

return function(H)
  local eq, ok = H.eq, H.ok
  local registry = require("lib.nvim.registry")

  ---@param fn function
  ---@return boolean raised
  ---@return string msg
  local function raises(fn)
    local good, err = pcall(fn)
    return not good, tostring(err)
  end

  -- order: registration order, never pairs() order
  local r = registry.new({ name = "t" })
  r:register("zeta", 1):register("alpha", 2):register("mid", 3)
  eq(table.concat(r:keys(), ","), "zeta,alpha,mid", "keys: registration order")
  eq(table.concat(r:all(), ","), "1,2,3", "all: values in registration order")
  eq(r:count(), 3, "count")
  eq(r:get("alpha"), 2, "get")
  eq(r:get("nope"), nil, "get: missing is nil")
  eq(r:has("mid"), true, "has")
  eq(r:has("nope"), false, "has: missing")

  -- the lists are copies
  local keys = r:keys()
  keys[#keys + 1] = "junk"
  table.remove(keys, 1)
  eq(
    table.concat(r:keys(), ","),
    "zeta,alpha,mid",
    "keys: a returned list does not reach the registry"
  )

  -- entries / find / all(pred)
  local entries = r:entries()
  eq(#entries, 3, "entries: one per key")
  eq(entries[2][1], "alpha", "entries: [1] is the key")
  eq(entries[2][2], 2, "entries: [2] is the value")
  local fk, fv = r:find(function(_, v)
    return v >= 2
  end)
  eq(fk, "alpha", "find: the first in registration order that matches")
  eq(fv, 2, "find: ... and its value")
  eq((r:find(function()
    return false
  end)), nil, "find: nothing matches")
  eq(
    table.concat(
      r:all(function(k)
        return k ~= "alpha"
      end),
      ","
    ),
    "1,3",
    "all(pred): filtered, order kept"
  )

  -- duplicates: replace keeps the position
  r:register("alpha", 20)
  eq(r:get("alpha"), 20, "replace: new value")
  eq(
    table.concat(r:keys(), ","),
    "zeta,alpha,mid",
    "replace: the position is kept, no duplicate key"
  )
  eq(r:count(), 3, "replace: count unchanged")

  local keep = registry.new({ on_duplicate = "keep" })
  keep:register("a", 1):register("a", 2)
  eq(keep:get("a"), 1, "on_duplicate = keep: the first one stays")
  local err_reg = registry.new({ name = "strict", on_duplicate = "error" })
  err_reg:register("a", 1)
  local raised, msg = raises(function()
    err_reg:register("a", 2)
  end)
  ok(raised and msg:find("already registered", 1, true) ~= nil, "on_duplicate = error: raises")
  ok(msg:find("strict", 1, true) ~= nil, "on_duplicate = error: ... naming the registry")
  eq(err_reg:get("a"), 1, "on_duplicate = error: the first one stays")

  -- unregister
  eq(r:unregister("alpha"), true, "unregister: existing")
  eq(r:unregister("alpha"), false, "unregister: missing")
  eq(table.concat(r:keys(), ","), "zeta,mid", "unregister: order of the rest kept")
  r:register("alpha", 5)
  eq(table.concat(r:keys(), ","), "zeta,mid,alpha", "unregister: a re-registered key goes last")

  -- validation
  local v = registry.new({
    name = "v",
    validate = function(key, value)
      if type(value) ~= "function" then
        return false, "needs a function"
      end
      return key ~= "bad"
    end,
  })
  v:register("good", function() end)
  local r1, m1 = raises(function()
    v:register("x", 5)
  end)
  ok(r1 and m1:find("needs a function", 1, true) ~= nil, "validate: the reason reaches the error")
  local r2 = raises(function()
    v:register("bad", function() end)
  end)
  ok(r2, "validate: a falsy answer without a reason refuses too")
  eq(v:has("x") or v:has("bad"), false, "validate: a refused entry is not stored")
  local r3, m3 = raises(function()
    registry
      .new({
        validate = function()
          error("kaput")
        end,
      })
      :register("k", 1)
  end)
  ok(
    r3 and m3:find("kaput", 1, true) ~= nil,
    "validate: a throwing validator is reported, with its message"
  )

  -- nil is refused
  ok(
    raises(function()
      r:register(nil, 1)
    end),
    "register: nil key"
  )
  ok(
    raises(function()
      r:register("k", nil)
    end),
    "register: nil value"
  )

  -- lazy loader: once, before the first read, and the loader may call register itself
  local loads = 0
  local lazy
  lazy = registry.new({
    loader = function()
      loads = loads + 1
      lazy:register("lua", "L")
      lazy:register("py", "P")
    end,
  })
  eq(loads, 0, "loader: not run at creation")
  lazy:register("early", "E") -- a write does not trigger it
  eq(loads, 0, "loader: not run by register")
  eq(lazy:get("lua"), "L", "loader: runs before the first read")
  eq(loads, 1, "loader: once")
  eq(
    table.concat(lazy:keys(), ","),
    "early,lua,py",
    "loader: entries registered before it keep their place"
  )
  lazy:keys()
  lazy:count()
  eq(loads, 1, "loader: not again")

  -- a loader that reads back (re-entrancy) does not recurse
  local reentered = 0
  local self_reading
  self_reading = registry.new({
    loader = function()
      reentered = reentered + 1
      self_reading:register("a", 1)
      self_reading:get("a") -- would recurse if `loaded` were set after the loader
    end,
  })
  eq(self_reading:get("a"), 1, "loader: a loader that reads its own registry works")
  eq(reentered, 1, "loader: ... without running twice")

  -- a loader that throws: the error reaches the reader, the registry is not left "loaded" half-filled
  local attempts = 0
  local flaky
  flaky = registry.new({
    loader = function()
      attempts = attempts + 1
      flaky:register("first", 1)
      if attempts == 1 then
        error("loader boom")
      end
      flaky:register("second", 2)
    end,
  })
  local lr, lm = raises(function()
    flaky:get("first")
  end)
  ok(
    lr and lm:find("loader boom", 1, true) ~= nil,
    "loader: its own error reaches the reading call"
  )
  eq(flaky:get("second"), 2, "loader: the next read runs it again and gets the full set")
  eq(attempts, 2, "loader: ... exactly once more")
  eq(
    table.concat(flaky:keys(), ","),
    "first,second",
    "loader: entries are not duplicated by the retry"
  )

  -- a retry after a throwing loader is no duplicate, even with on_duplicate = "error"
  local strict, strict_runs = nil, 0
  strict = registry.new({
    on_duplicate = "error",
    loader = function()
      strict_runs = strict_runs + 1
      strict:register("a", 1)
      if strict_runs == 1 then
        error("boom")
      end
      strict:register("b", 2)
    end,
  })
  ok(raises(function()
    strict:count()
  end), "strict loader: the first read raises the loader's error")
  eq(strict:count(), 2, "strict loader: the retry completes instead of failing on 'a' again")
  eq(table.concat(strict:keys(), ","), "a,b", "strict loader: ... with each key once")
  ok(raises(function()
    strict:register("a", 9)
  end), "strict loader: a real duplicate afterwards is still refused")

  -- unregister runs the loader first: a known entry can be removed before anything read the registry
  local known
  known = registry.new({
    loader = function()
      known:register("a", 1)
      known:register("b", 2)
    end,
  })
  eq(known:unregister("a"), true, "unregister: a loader-registered entry, before any read")
  eq(table.concat(known:keys(), ","), "b", "unregister: ... and the rest stays")

  -- reset: empty, and the loader runs again before the next read
  lazy:reset()
  eq(lazy:count(), 2, "reset: the loader re-registers the known entries on the next read")
  eq(loads, 2, "reset: the loader ran again")
  eq(lazy:has("early"), false, "reset: what was registered by hand is gone")
  local plain = registry.new()
  plain:register("a", 1)
  plain:reset()
  eq(plain:count(), 0, "reset: without a loader it is simply empty")
  eq(#plain:keys(), 0, "reset: no keys")

  -- two registries are independent
  local a, b = registry.new(), registry.new()
  a:register("k", 1)
  eq(b:has("k"), false, "two registries do not share entries")

  -- non-string keys work
  local fn_key = function() end
  local k = registry.new()
  k:register(fn_key, "f"):register(42, "n")
  eq(k:get(fn_key), "f", "a function as key")
  eq(k:get(42), "n", "a number as key")

  -- bad options
  ok(
    raises(function()
      registry.new({ on_duplicate = "overwrite" })
    end),
    "new: an unknown on_duplicate is refused"
  )
end
