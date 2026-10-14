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

  -- ── scrub: the install path up to lua/ (known limit: a space) ──
  eq(
    errors.scrub("/home/me/.local/share/nvim/lazy/x.nvim/lua/x_nvim/a.lua:12: boom"),
    "x_nvim/a.lua:12: boom"
  )
  eq(errors.scrub("C:\\Users\\me\\x.nvim\\lua\\x_nvim\\a.lua:3: boom"), "x_nvim\\a.lua:3: boom")
  eq(errors.scrub("plain text"), "plain text")
  eq(
    errors.scrub("'/a b/lua/m.lua:1: x'"),
    "'/a m.lua:1: x'",
    "known limit, see README: a path with a space is cut at the space, the part after it is the only start the cut can find"
  )
  eq(
    errors.scrub("/home/me/.config/nvim/init.lua:5: boom"),
    "/home/me/.config/nvim/init.lua:5: boom",
    "a path without a lua directory is not touched at all"
  )
  eq(errors.scrub("x/lua/lua/y"), "y", "overlapping /lua/ marks: the cut is after the last one")
  eq(errors.scrub("a/lua/ b/lua/c"), " c", "each token is cut at its own last /lua/")
  eq(errors.scrub("/lua/"), "", "nothing left of a token that is only the mark")
  eq(errors.scrub("a/lua"), "a/lua", "a mark needs a separator on both sides")
  eq(errors.scrub("xlua/y"), "xlua/y", "and on the left too")
  eq(errors.scrub("a\\lua/b"), "b", "either separator, also mixed")
  -- a path in quotes (how a message often shows one): the quote is no part of the path, it stays, the install path goes
  eq(
    errors.scrub("'C:/x/lua/a.lua:1: boom'"),
    "'a.lua:1: boom'",
    "single quotes around the whole message"
  )
  eq(errors.scrub('"/opt/x/lua/m/a.lua:5: boom"'), '"m/a.lua:5: boom"', "double quotes")
  eq(
    errors.scrub("cannot read '/opt/x/lua/m/a.lua' and \"/opt/y/lua/n/b.lua\""),
    "cannot read 'm/a.lua' and \"n/b.lua\"",
    "a quoted path in the middle of a text, either kind of quote"
  )

  -- scrub and classify are linear in the length of a long token: the text of an `internal` error may echo a value
  -- of the request (up to 256 KiB), and one pattern that backtracks over a token froze the editor for minutes
  local function fast(label, fn)
    local t0 = vim.uv.hrtime()
    local result = fn()
    local ms = (vim.uv.hrtime() - t0) / 1e6
    ok(ms < 2000, ("%s is linear in a long token (took %d ms)"):format(label, ms))
    return result
  end
  local long = ("a"):rep(50000)
  ok(fast("scrub", function()
    return errors.scrub(long)
  end) == long, "a long token without a mark is unchanged")
  local classified = fast("classify", function()
    return errors.classify("bad request " .. long)
  end)
  eq(classified.code, "internal")
  ok(classified.message == "bad request " .. long, "classify keeps the long token")
  ok(fast("scrub of separators", function()
    return errors.scrub(("ab/"):rep(16000))
  end) == ("ab/"):rep(16000), "a long token full of separators and no mark is unchanged")
  ok(fast("scrub next to a mark", function()
    return errors.scrub(long .. " x/lua/y")
  end) == long .. " y", "a mark in another token does not make the long one expensive")

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
  -- every key of DETAIL_KEYS reaches the document (a key dropped from the list drops its detail without a sound)
  eq(
    errors.classify("m", {
      code = "x",
      id = 1,
      key = 2,
      expected = 3,
      actual = 4,
      written = 5,
      writes = 6,
      path = "/secret",
    }).details,
    { id = 1, key = 2, expected = 3, actual = 4, written = 5, writes = 6 },
    "all six detail keys, and still not the path"
  )
  -- the message of a coded error is the TEXT of whatever came back, not the value itself
  for _, case in ipairs({
    { 42, "42" },
    { true, "true" },
    { { message = "from a table" }, "from a table" },
    { {}, "error value of type table" },
    { function() end, "error value of type function" },
  }) do
    local coded = errors.classify(case[1], { code = "x" })
    eq(type(coded.message), "string", "a text for " .. type(case[1]))
    eq(coded.message, case[2], "the text of a " .. type(case[1]))
    eq(coded.code, "x")
  end
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
  -- a third value that is no table is no `info` (what a function hands on as its third value may be anything)
  for _, junk in ipairs({ true, 5, "conflict", function() end }) do
    local survived, from_junk = pcall(errors.classify, "no such thing", junk)
    ok(survived, "classify does not raise on a third value of type " .. type(junk))
    eq(from_junk.code, "not_found", "the text decides, " .. type(junk))
  end
  eq(errors.classify("x", false).code, "internal", "false is no info either")

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

  -- ── text: whatever came back, as a text that is the same on every call, and never a throw ──
  eq(errors.text("plain"), "plain")
  eq(errors.text(42), "42")
  eq(errors.text(true), "true")
  eq(errors.text(nil), "nil")
  eq(errors.text({ message = "boom" }), "boom", "an error table without a code: its message")
  eq(errors.classify({ message = "boom" }).message, "boom")
  eq(errors.classify({ message = "boom" }).code, "internal")
  eq(
    errors.text(setmetatable({}, {
      __tostring = function()
        return "custom"
      end,
    })),
    "custom",
    "an error object that prints itself keeps its own text"
  )
  local plain_tbl = errors.classify({})
  eq(plain_tbl.message, "error value of type table", "a table with no message names its type")
  eq(errors.classify({}), plain_tbl, "and is the same on the next call: no address")
  eq(
    errors.classify({ message = 5 }).message,
    "error value of type table",
    "a message that is no text"
  )
  eq(errors.classify(function() end).message, "error value of type function")
  local timer = vim.uv.new_timer()
  local timer_text = errors.classify(timer).message
  timer:close()
  ok(not timer_text:find("0x", 1, true), "a userdata is not shown with its address: " .. timer_text)
  local thrower = setmetatable({}, {
    __tostring = function()
      error("no")
    end,
  })
  local survived, thrown = pcall(errors.classify, thrower)
  ok(survived, "an error object whose __tostring raises does not make classify raise")
  eq(thrown.message, "error value of type table")
  eq(thrown.code, "internal")
  local liar = setmetatable({}, {
    __tostring = function()
      return 5
    end,
  })
  eq(errors.text(liar), "error value of type table", "a __tostring that is no text is ignored")
  local hostile = setmetatable({}, {
    __index = function()
      error("no")
    end,
  })
  eq(errors.text(hostile), "error value of type table", "a message that cannot be read")
  eq(
    errors.classify({ message = "m" }, { code = "io" }).message,
    "m",
    "also with a code from the source"
  )

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

  -- ── check_patterns: the shape of the plugin's patterns, told where they are handed in ──
  eq(errors.check_patterns(mine), nil, "well formed patterns")
  eq(errors.check_patterns({}), nil, "no patterns at all")
  eq(
    errors.check_patterns({ { code = "io", find = { "a", "b" }, retryable = true } }),
    nil,
    "retryable is not checked: only the boolean true counts"
  )
  eq(
    errors.check_patterns({ { code = "io", find = {} } }),
    nil,
    "a rule that never matches is no fault"
  )
  local good_rule = { code = "io", find = { "a" } }
  for name, bad in pairs({
    ["a string for find"] = { { code = "not_found", find = "unknown" } },
    ["no find"] = { { code = "not_found" } },
    ["a rule that is false"] = { false },
    ["a rule that is a text"] = { "unknown" },
    ["no code"] = { { find = { "x" } } },
    ["a code that is no text"] = { { code = 5, find = { "x" } } },
    ["a needle that is a table"] = { { code = "io", find = { {} } } },
    ["a needle that is a number"] = { { code = "io", find = { 1 } } },
    ["find that is no list"] = { { code = "io", find = { a = "x" } } },
  }) do
    local problem = errors.check_patterns(bad)
    ok(
      type(problem) == "string" and problem:find("patterns[1]", 1, true),
      name .. " names the rule: " .. tostring(problem)
    )
    ok(not problem:find("%.lua:%d+:"), name .. ": no position, the message is returned as a value")
    local later = errors.check_patterns({ good_rule, bad[1] })
    ok(
      type(later) == "string" and later:find("patterns[2]", 1, true),
      name .. " is found behind a good rule"
    )
  end
  eq(
    errors.check_patterns({ { code = "io", find = "x" } }),
    "patterns[1].find must be a list of strings"
  )
  eq(errors.check_patterns({ {} }), "patterns[1].code must be a string")
  eq(errors.check_patterns({ 1 }), "patterns[1] must be a table")
  for _, bad in ipairs({ "oops", 5, true, { a = 1 } }) do
    eq(errors.check_patterns(bad), "patterns must be a list", vim.inspect(bad))
  end
end
