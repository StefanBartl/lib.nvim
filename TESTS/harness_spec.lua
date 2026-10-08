-- TESTS/harness_spec.lua -- the shared helper `H.with_patched` itself
--
-- Many specs patch module members through it. What they rely on: the original comes back
-- whatever `fn` does, and a failure inside `fn` reads exactly as `fn` raised it -- `assert(ok, err)`
-- used to put "TESTS/harness.lua:62:" in front of the message of every one of those specs.

return function(H)
  local target = { fn = "original" }

  H.with_patched(target, "fn", "patched", function()
    H.eq(target.fn, "patched", "with_patched: the replacement is in place while fn runs")
  end)
  H.eq(target.fn, "original", "with_patched: the original is back after fn returned")

  local ok, err = pcall(H.with_patched, target, "fn", "patched", function()
    error("boom", 0)
  end)
  H.eq(ok, false, "with_patched: a raising fn raises")
  H.eq(target.fn, "original", "with_patched: the original is back after fn raised")
  H.eq(err, "boom", "with_patched: the error is re-raised unchanged")

  -- A failed assertion keeps the position of the spec line that failed, and no other.
  local _, assertion = pcall(H.with_patched, target, "fn", "patched", function()
    H.eq(1, 2, "demo")
  end)
  H.ok(
    type(assertion) == "string" and assertion:find("FAIL demo: expected 2, got 1", 1, true),
    "with_patched: an assertion failure keeps its message"
  )
  H.ok(
    not assertion:find("harness.lua", 1, true),
    "with_patched: no position inside TESTS/harness.lua in front of the message: " .. assertion
  )

  -- Not only strings are errors.
  local payload = { code = 7 }
  local _, raised = pcall(H.with_patched, target, "fn", "patched", function()
    error(payload, 0)
  end)
  H.ok(rawequal(raised, payload), "with_patched: a table error is passed on as the same table")

  -- A key that was absent is absent again.
  H.with_patched(target, "extra", 1, function()
    H.eq(target.extra, 1, "with_patched: a new key is set while fn runs")
  end)
  H.eq(target.extra, nil, "with_patched: a key that was absent is absent again")
end
