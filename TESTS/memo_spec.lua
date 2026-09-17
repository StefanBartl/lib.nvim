-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/memo_spec.lua — lib.lua.memo
--
-- The key builder is the whole subject here. It used to be
-- `table.concat({ ... }, "\31")`, which throws on any argument `concat` will
-- not take: a boolean, a table, a TSNode. Callers hit
-- `invalid value (userdata) at index 1 in table for 'concat'` raised from
-- inside the wrapper, far from their own call site -- which is how a whole
-- Tree-sitter code path in my.nvim sat broken behind a second defect.
--
-- The collision cases matter as much as the throwing ones: a key that silently
-- merges two different calls hands back the wrong cached value, which is worse
-- than an error.

return function(H)
  local eq, ok = H.eq, H.ok

  local memo = require("lib.lua.memo")

  -- ----------------------------------------------------- it caches at all
  local calls = 0
  local double = memo.fn(function(n)
    calls = calls + 1
    return n * 2
  end)

  eq(double(21), 42, "memo.fn: returns the wrapped function's value")
  eq(double(21), 42, "memo.fn: same argument, same value")
  eq(calls, 1, "memo.fn: the second call was a cache hit")
  eq(double(1), 2, "memo.fn: a different argument computes again")
  eq(calls, 2, "memo.fn: ...and that was a miss")

  -- ------------------------------------------- argument types that threw
  -- Each of these raised from inside the memo wrapper before the key builder
  -- was replaced.
  local seen = {}
  local echo = memo.fn(function(v)
    seen[#seen + 1] = v
    return { v }
  end)

  ok(pcall(echo, true), "memo.fn: a boolean argument does not throw")
  ok(pcall(echo, nil), "memo.fn: a nil argument does not throw")
  ok(pcall(echo, {}), "memo.fn: a table argument does not throw")
  ok(pcall(echo, print), "memo.fn: a function argument does not throw")
  ok(pcall(echo, coroutine.create(function() end)), "memo.fn: a thread argument does not throw")

  -- The userdata case is the one the my.nvim defect was actually about.
  -- vim.uv handles are userdata that is cheap to make and safe to discard.
  local handle = vim.uv.new_timer()
  ok(pcall(echo, handle), "memo.fn: a userdata argument does not throw")
  handle:close()

  -- --------------------------------------------------- key collisions
  local recorded = {}
  local record = memo.fn(function(v)
    recorded[#recorded + 1] = type(v)
    return type(v)
  end)

  eq(record(1), "number", "memo.fn: number 1")
  eq(record("1"), "string", 'memo.fn: string "1" is not the same key as number 1')

  local sep = memo.fn(function(a, b)
    return tostring(a) .. "|" .. tostring(b)
  end)

  -- The separator is \31, so a string containing it could forge a tuple
  -- boundary. The type tags keep the two apart.
  eq(sep("a\31b", nil), "a\31b|nil", "memo.fn: a separator inside an argument")
  eq(sep("a", "b"), "a|b", "memo.fn: ...does not collide with a real two-argument call")

  -- A nil in the middle of a tuple has no reliable `#`, so these two used to
  -- be able to land on the same key.
  local arity = memo.fn(function(a, b)
    return tostring(a) .. "/" .. tostring(b)
  end)

  eq(arity(nil, 2), "nil/2", "memo.fn: leading nil is part of the key")
  eq(arity(2), "2/nil", "memo.fn: ...and is distinct from the shorter call")

  -- --------------------------------------------------- unknown options
  -- `weak` was read by nobody and accepted in silence for as long as memo.fn
  -- existed. It could not have worked -- the cache keys on strings, and weak
  -- tables do not collect string keys.
  local threw, err = pcall(memo.fn, function() end, { weak = "k", size = 8 })
  ok(not threw, "memo.fn: an unknown option is refused")
  ok(tostring(err):match("weak") ~= nil, "memo.fn: ...and the message names it")

  ok(pcall(memo.fn, function() end, { size = 8 }), "memo.fn: size is accepted")
  ok(pcall(memo.fn, function() end, 8), "memo.fn: a bare capacity number still works")

  -- ------------------------------------------------------- custom keyer
  local by_id = memo.fn(function(t)
    return t.id * 10
  end, {
    keyer = function(t)
      return "id:" .. tostring(t.id)
    end,
  })

  eq(by_id({ id = 3 }), 30, "memo.fn: custom keyer computes")
  eq(by_id({ id = 3 }), 30, "memo.fn: a different table with the same id is a hit")

  -- --------------------------------------------------------- memoize2
  -- Keys tables by content rather than address, which is its whole reason to
  -- exist; it had the same nil-arity hole as memoize.
  local m2 = require("lib.lua.memo.memo")
  local shape_calls = 0
  local shape = m2.memoize2(function(t)
    shape_calls = shape_calls + 1
    return t and t.kind or "none"
  end)

  eq(shape({ kind = "a" }), "a", "memoize2: computes")
  eq(shape({ kind = "a" }), "a", "memoize2: an equal table is a cache hit")
  eq(shape_calls, 1, "memoize2: ...and did not recompute")
  eq(shape({ kind = "b" }), "b", "memoize2: a different table computes again")
end
