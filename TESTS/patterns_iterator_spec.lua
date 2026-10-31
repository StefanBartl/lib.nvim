-- TESTS/patterns_iterator_spec.lua — lib.lua.patterns.iterator
return function(H)
  local eq, ok = H.eq, H.ok
  local iterator = require("lib.lua.patterns.iterator")

  local function join(t)
    return table.concat(t, ",")
  end

  eq(join(iterator.of({ 1, 2, 3 }):collect()), "1,2,3", "of + collect")
  eq(join(iterator.range(1, 5):collect()), "1,2,3,4,5", "range inclusive")
  eq(join(iterator.range(5, 1, -2):collect()), "5,3,1", "negative step")
  eq(join(iterator.range(1, 0):collect()), "", "empty range")
  ok(not pcall(iterator.range, 1, 2, 0), "step 0 raises")

  local pipeline = iterator
    .range(1, 20)
    :filter(function(x)
      return x % 2 == 0
    end)
    :map(function(x)
      return x * x
    end)
    :take(3)
  eq(join(pipeline:collect()), "4,16,36", "filter, map, take chain")

  eq(join(iterator.range(1, 6):drop(4):collect()), "5,6", "drop")
  eq(join(iterator.range(1, 2):drop(5):collect()), "", "drop more than available")
  eq(join(iterator.range(1, 6):take(0):collect()), "", "take 0")

  -- laziness: map must not run beyond what take asks for
  local calls = 0
  iterator
    .range(1, 1000)
    :map(function(x)
      calls = calls + 1
      return x
    end)
    :take(3)
    :collect()
  eq(calls, 3, "lazy: only the needed elements are mapped")

  local it = iterator.of({ "a", "b" })
  eq(it:peek(), "a", "peek")
  eq(it:peek(), "a", "peek does not consume")
  ok(it:has_next(), "has_next")
  eq(it:next(), "a", "next after peek")
  eq(it:next(), "b", "next")
  ok(it:next() == nil and not it:has_next(), "exhausted")

  eq(
    iterator.range(1, 4):reduce(function(a, v)
      return a + v
    end, 0),
    10,
    "reduce"
  )
  local seen = {}
  iterator.of({ "x", "y" }):each(function(v)
    seen[#seen + 1] = v
  end)
  eq(join(seen), "x,y", "each")
  local sum = 0
  for v in iterator.range(1, 3):iter() do
    sum = sum + v
  end
  eq(sum, 6, "iter works in a generic for")
  local n = 0
  for _ in
    iterator
      .from_fn(function()
        n = n + 1
        return n <= 2 and n or nil
      end)
      :iter()
  do
  end
  eq(n, 3, "from_fn stops at nil")
end
