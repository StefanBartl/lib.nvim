-- TESTS/patterns_decorator_spec.lua — lib.lua.patterns.decorator
return function(H)
  local eq, ok = H.eq, H.ok
  local decorator = require("lib.lua.patterns.decorator")

  local log = {}
  local function base(x)
    log[#log + 1] = "base"
    return x * 2
  end

  local function tag(name)
    return function(fn)
      return function(...)
        log[#log + 1] = name .. ">"
        local r = fn(...)
        log[#log + 1] = "<" .. name
        return r
      end
    end
  end

  local f = decorator.wrap(base, tag("outer"), tag("inner"))
  eq(f(4), 8, "result passes through")
  eq(table.concat(log, ","), "outer>,inner>,base,<inner,<outer", "first listed is outermost")

  log = {}
  local g = decorator.wrap(
    base,
    decorator.before(function(x)
      log[#log + 1] = "before" .. x
    end),
    decorator.after(function(results, x)
      log[#log + 1] = "after" .. results[1] .. "/" .. x
    end)
  )
  eq(g(3), 6, "before/after keep the result")
  eq(table.concat(log, ","), "before3,base,after6/3", "hooks run in order with their arguments")

  local guarded = decorator.guard(function(x)
    return x > 0
  end, function()
    return "denied"
  end)(base)
  eq(guarded(2), 4, "guard lets matching calls through")
  eq(guarded(-1), "denied", "guard falls back")
  eq(
    decorator.guard(function()
      return false
    end)(base)(1),
    nil,
    "guard without otherwise returns nothing"
  )

  local clock = 0
  local seen
  local slow = decorator.timed(function(ms, x)
    seen = { ms, x }
  end, function()
    return clock
  end)(function(x)
    clock = clock + 0.25
    return x, "two"
  end)
  local r1, r2 = slow("v")
  ok(r1 == "v" and r2 == "two", "timed keeps multiple results")
  ok(seen[1] == 250 and seen[2] == "v", "timed reports milliseconds and the arguments")

  local boom = decorator.timed(function(ms)
    seen = ms
  end, function()
    return 0
  end)(function()
    error("bad", 0)
  end)
  local good, err = pcall(boom)
  ok(not good and err == "bad", "timed re-raises errors")
  eq(seen, 0, "and still reports")
  eq(decorator.wrap(base)(1), 2, "wrap without decorators returns the function")

  -- trailing nils in the results must survive after/timed
  local function three()
    return "a", nil, nil
  end
  eq(
    select("#", decorator.wrap(three, decorator.after(function() end))()),
    3,
    "after keeps trailing nil results"
  )
  eq(
    select(
      "#",
      decorator.wrap(
        three,
        decorator.timed(function() end, function()
          return 0
        end)
      )()
    ),
    3,
    "timed keeps trailing nil results"
  )
end
