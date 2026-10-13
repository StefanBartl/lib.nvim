-- TESTS/contract_errors_spec.lua -- lib.nvim.contract.errors: the error vocabulary of a machine contract.

return function(H)
  local ok = H.ok

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end
  local errors = require("lib.nvim.contract.errors")

  -- ── the vocabulary ──
  local sorted = vim.deepcopy(errors.CODES)
  table.sort(sorted)
  eq(errors.CODES, sorted, "the codes are sorted")
  local seen = {}
  for _, code in ipairs(errors.CODES) do
    ok(not seen[code], code .. " is listed once")
    seen[code] = true
  end
  for _, code in ipairs({ "invalid_argument", "not_found", "conflict", "locked", "internal", "io" }) do
    ok(vim.tbl_contains(errors.CODES, code), code .. " is a code")
  end

  -- ── fail ──
  eq(errors.fail("io", "boom"), { code = "io", message = "boom", retryable = false })
  eq(errors.fail("locked", "busy", true).retryable, true)
  eq(
    errors.fail("io", "boom", "yes" --[[@as boolean]]).retryable,
    false,
    "only the boolean true counts"
  )

  -- ── scrub: no path of this machine ──
  eq(
    errors.scrub("/home/me/.local/share/nvim/lazy/x.nvim/lua/x_nvim/a.lua:12: boom"),
    "x_nvim/a.lua:12: boom"
  )
  eq(errors.scrub("C:\\Users\\me\\x.nvim\\lua\\x_nvim\\a.lua:3: boom"), "x_nvim\\a.lua:3: boom")
  eq(errors.scrub("plain text"), "plain text")
  eq(
    errors.scrub("'/a b/lua/m.lua:1: x'"),
    "'/a m.lua:1: x'",
    "a path with a space is cut at the space: only the part after it is a start the pattern can find"
  )

  -- ── classify: an error that is already one passes through unchanged ──
  local given = { code = "conflict", message = "m", retryable = false }
  ok(errors.classify(given) == given, "the same table")

  -- ── classify with the code given at the source (the third value) ──
  local e = errors.classify(
    "file changed",
    { code = "conflict", id = "a/b", expected = "x", actual = "y", path = "/secret/p" }
  )
  eq(e.code, "conflict")
  eq(e.message, "file changed")
  eq(e.retryable, false)
  eq(e.details, { id = "a/b", expected = "x", actual = "y" }, "ids and values, never a path")
  eq(errors.classify("m", { code = "io" }).details, nil, "no details when there are none")
  eq(errors.classify("busy", { code = "locked" }).retryable, true, "locked is always retryable")
  eq(
    errors.classify("m", { code = "io", retryable = true }).retryable,
    true,
    "the source may say so"
  )
  eq(
    errors.classify("m", { code = "io", retryable = "yes" }).retryable,
    false,
    "only the boolean true counts"
  )
  eq(
    errors.classify("m", { code = "io", id = "a", secret = "b" }, { detail_keys = { "secret" } }).details,
    { secret = "b" },
    "the plugin may name its own detail keys"
  )

  -- ── classify by the text of a message (the built-in patterns) ──
  local function code_of(text, opts)
    return errors.classify(text, nil, opts).code
  end
  eq(code_of("x is not a directory"), "not_found")
  eq(code_of("no such file"), "not_found")
  eq(code_of("name already exists"), "exists")
  eq(code_of("rollback incomplete: a.md"), "rollback_incomplete")
  for _, text in ipairs({
    "cannot list a",
    "cannot read a",
    "cannot write a",
    "cannot create a",
    "cannot update a",
    "cannot lock a",
    "permission denied",
  }) do
    eq(code_of(text), "io", text)
  end
  local busy = errors.classify("a is being written by another process")
  eq(busy.code, "locked")
  eq(busy.retryable, true, "a lock that is held right now can be asked again")
  local stuck = errors.classify("a has a lock that cannot be taken over: remove it by hand (l)")
  eq(stuck.code, "lock_stuck")
  eq(stuck.retryable, false)
  eq(
    errors.classify("not found: x").code,
    "internal",
    "'not found' alone is no pattern: the plugin names its own"
  )

  -- ── precedence: the order of the built-in patterns is part of the contract ──
  eq(code_of("no such file, already exists"), "not_found", "not_found before exists")
  eq(code_of("already exists, cannot write"), "exists", "exists before io")
  eq(code_of("cannot lock x (permission)"), "io", "cannot lock is io, not locked")

  -- ── internal: the message is scrubbed, and only that one ──
  local bug = errors.classify("/opt/x/lua/m/a.lua:5: attempt to index nil")
  eq(bug.code, "internal")
  eq(bug.message, "m/a.lua:5: attempt to index nil", "no path of this machine")
  eq(
    errors.classify("cannot read /opt/x/lua/y").message,
    "cannot read /opt/x/lua/y",
    "a coded message is kept as it is"
  )
  eq(errors.classify(42).message, "42", "whatever comes back is made a text")
  eq(errors.classify(nil).code, "internal")

  -- ── the plugin's own patterns come first ──
  local mine = {
    { code = "not_found", find = { "unknown area", "vault not found" } },
    { code = "invalid_argument", find = { "nothing to set" } },
  }
  eq(code_of("unknown area 'x'", { patterns = mine }), "not_found")
  eq(code_of("nothing to set", { patterns = mine }), "invalid_argument")
  eq(code_of("unknown area 'x'"), "internal", "without the plugin's patterns it is not recognised")
  eq(
    code_of("cannot read a", { patterns = mine }),
    "io",
    "a message the plugin does not know falls to the built-in ones"
  )
  eq(
    code_of("unknown area, cannot read", { patterns = mine }),
    "not_found",
    "the plugin's pattern wins over a built-in one"
  )
  eq(
    code_of("already exists", { patterns = { { code = "conflict", find = { "already exists" } } } }),
    "conflict",
    "and may take over a built-in text"
  )
  local soft = errors.classify(
    "slow down",
    nil,
    { patterns = { { code = "locked", find = { "slow down" }, retryable = true } } }
  )
  eq(soft.retryable, true, "a pattern may be retryable")
  eq(
    errors.classify("/o/lua/m.lua:1: boom unknown", nil, { patterns = mine }).message,
    "m.lua:1: boom unknown",
    "a message no pattern matches is still scrubbed"
  )
end
