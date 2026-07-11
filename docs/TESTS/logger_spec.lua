-- docs/TESTS/logger_spec.lua — lib.nvim.logger behaviour.

return function(H)
  local eq, ok = H.eq, H.ok
  local L = require("lib.nvim.logger")

  -- Always start from a clean global state (other specs may run first).
  L.set_enabled(true)
  L.set_level(nil)
  L.only_tags(nil)

  -- ------------------------------------------------------------------ record
  local file = H.tmpfile("-log.jsonl")
  local log = L.new({
    name = "spec",
    level = "trace",
    notify_level = "off",
    file = file,
    capture = false,
    history = 10,
  })

  log.info("hello", { a = 1, nested = { b = 2 } })
  log.debug("dbg", function()
    return { built = "lazily" }
  end)
  log.warn("watch", nil, { tags = { "net" } })
  log.error("boom", { path = "x" })
  eq(#log.snapshot(), 4, "ring holds 4 records")

  local rec = log.snapshot()[1]
  eq(rec.msg, "hello", "record msg preserved")
  eq(rec.ctx.nested.b, 2, "nested context preserved")
  eq(rec.level_name, "INFO", "level name resolved")

  -- thunk context is resolved
  eq(log.snapshot()[2].ctx.built, "lazily", "thunk context resolved")

  -- ------------------------------------------------------------- level gate
  log.set_level("warn")
  log.debug("dropped by level")
  eq(#log.snapshot(), 4, "sub-threshold level is gated")
  log.set_level("trace")

  -- ---------------------------------------------------------- master switch
  L.set_enabled(false)
  log.error("dropped by master switch")
  eq(#log.snapshot(), 4, "global disable suppresses everything")
  L.set_enabled(true)

  -- -------------------------------------------------------------------- tags
  L.disable_tag("net")
  log.info("tagged off", nil, { tags = { "net" } })
  eq(#log.snapshot(), 4, "disabled tag is dropped")
  L.enable_tag("net")
  log.info("tagged on", nil, { tags = { "net" } })
  eq(#log.snapshot(), 5, "re-enabled tag passes")

  L.only_tags({ "keep" })
  log.info("no tag -> dropped")
  log.info("kept", nil, { tags = { "keep" } })
  eq(#log.snapshot(), 6, "only_tags whitelist keeps only tagged")
  L.only_tags(nil)

  -- ------------------------------------------------------------- ring bound
  for i = 1, 50 do
    log.info("spam " .. i)
  end
  eq(#log.snapshot(), 10, "ring buffer is bounded to history size")

  -- ---------------------------------------------------------------- redact
  local rlog =
    L.new({ name = "redact", notify_level = "off", file = false, redact = { "password" } })
  rlog.info("login", { user = "sb", password = "secret" })
  local r = rlog.snapshot()[1]
  eq(r.ctx.password, "<redacted>", "redacted key scrubbed")
  eq(r.ctx.user, "sb", "non-redacted key intact")

  -- ------------------------------------------------------------------ guard
  local ran = false
  local wrapped = log.wrap(function()
    ran = true
    error("kaboom")
  end, "risky")
  wrapped()
  ok(ran, "wrapped fn executed")
  local last = log.snapshot()[#log.snapshot()]
  ok(last.msg:find("guard caught error"), "guard recorded the error")
  ok(last.ctx.traceback:find("kaboom"), "traceback captured")

  -- guard re-raises, wrap does not
  local ok_call = pcall(log.guard(function()
    error("x")
  end, "g"))
  eq(ok_call, false, "guard re-raises")
  local ok_wrap = pcall(log.wrap(function()
    error("x")
  end, "w"))
  eq(ok_wrap, true, "wrap swallows")

  -- ------------------------------------------------------------- file sink
  local lines = H.read_lines(file)
  ok(#lines > 0, "file sink wrote lines")
  local decoded = vim.json.decode(lines[1])
  eq(decoded.msg, "hello", "first JSONL line decodes to first record")
  for i, line in ipairs(lines) do
    ok(pcall(vim.json.decode, line), "line " .. i .. " is valid JSON")
  end

  -- -------------------------------------------------------------- flush/clear
  local file2 = H.tmpfile("-flush.jsonl")
  local flog =
    L.new({ name = "flush", notify_level = "off", file = file2, capture = false, history = 5 })
  flog.info("a")
  flog.info("b")
  ok(flog.flush(), "flush returns true when file sink present")
  flog.clear()
  eq(#flog.snapshot(), 0, "clear empties the ring")
end
