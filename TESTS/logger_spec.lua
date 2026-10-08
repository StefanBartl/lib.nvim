-- TESTS/logger_spec.lua — lib.nvim.logger behaviour.

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

  -- ---------------------------------------------------------------- counters
  -- Tallies deliberately write no record: the point is to count an event that
  -- happens too often to log and read the total once.
  local clog = L.new({ name = "counters", notify_level = "off", file = false, capture = false })
  eq(clog.count("miss"), 1, "count() starts at 1")
  eq(clog.count("miss"), 2, "count() increments")
  eq(clog.count("hit"), 1, "counters are independent per key")
  eq(clog.counters().miss, 2, "counters() reports the tally")
  eq(#clog.snapshot(), 0, "counting writes no records")

  -- counters() must hand out a copy, or a caller could corrupt the tallies.
  local snapshot = clog.counters()
  snapshot.miss = 999
  eq(clog.counters().miss, 2, "counters() returns a copy")

  -- -------------------------------------------------------------- add_sink
  local slog = L.new({ name = "sinks", notify_level = "off", file = false, capture = false })
  local seen = {}
  slog.add_sink(function(record)
    seen[#seen + 1] = record.msg
  end)
  slog.info("through the sink")
  eq(seen[1], "through the sink", "a registered sink receives records")

  -- A sink below the level gate must not fire: gating happens before fan-out.
  slog.set_level("error")
  slog.info("gated out")
  eq(#seen, 1, "extra sinks respect the level gate")

  -- A throwing sink must not break logging for anything else.
  slog.set_level("trace")
  slog.add_sink(function()
    error("bad sink")
  end)
  local ok_after_bad = pcall(slog.info, "after a bad sink")
  eq(ok_after_bad, true, "a failing sink does not break the logger")
  eq(seen[#seen], "after a bad sink", "the healthy sink still ran")

  -- A non-function is ignored rather than blowing up at emit time.
  ---@diagnostic disable-next-line: param-type-mismatch
  slog.add_sink("not a function")
  eq(pcall(slog.info, "still fine"), true, "add_sink ignores a non-function")
  -- ------------------------------------------- nothing is registered at require
  -- A plugin creates its logger at `require` time; that must not register a
  -- command or an augroup (LUA-92). The command follows shortly after, the
  -- crash-capture group with the first record.
  do
    local saved = {}
    for k in pairs(package.loaded) do
      if k == "lib.nvim.logger" or k:find("^lib%.nvim%.logger%.") then
        saved[k] = package.loaded[k]
        package.loaded[k] = nil
      end
    end
    pcall(vim.api.nvim_del_user_command, "LibLogger")
    pcall(vim.api.nvim_del_augroup_by_name, "lib_logger_lazyreq")

    local F = require("lib.nvim.logger")
    local lfile = H.tmpfile("-lazy.jsonl")
    local lazylog = F.new({ name = "lazyreq", notify_level = "off", file = lfile })
    eq(vim.fn.exists(":LibLogger"), 0, "new() registers no command synchronously")
    eq(
      pcall(vim.api.nvim_get_autocmds, { group = "lib_logger_lazyreq" }),
      false,
      "new() creates no augroup"
    )

    ok(
      vim.wait(2000, function()
        return vim.fn.exists(":LibLogger") == 2
      end, 10),
      "the command appears shortly after the first logger"
    )

    lazylog.info("first record")
    local lazy_armed = vim.api.nvim_get_autocmds({ group = "lib_logger_lazyreq" })
    eq(#lazy_armed, 1, "the first record arms crash capture")
    -- Counting the autocmds proves nothing about "once": arming re-creates the
    -- group with `clear = true`, so one autocmd is what a re-arming leaves too.
    -- A re-arming gives the autocmd a new id, so the id is what is compared.
    local lazy_id = lazy_armed[1].id
    lazylog.info("second record")
    local lazy_again = vim.api.nvim_get_autocmds({ group = "lib_logger_lazyreq" })
    eq(#lazy_again, 1, "capture is still one autocmd")
    eq(lazy_again[1].id, lazy_id, "capture is armed once: the second record did not re-arm")

    eq(F.install_command(), true, "install_command() is idempotent")
    pcall(vim.api.nvim_del_augroup_by_name, "lib_logger_lazyreq")

    for k in pairs(package.loaded) do
      if k == "lib.nvim.logger" or k:find("^lib%.nvim%.logger%.") then
        package.loaded[k] = nil
      end
    end
    for k, v in pairs(saved) do
      package.loaded[k] = v
    end
  end

  -- ------------------------------------------- first record in a fast event
  -- A plugin creates its logger at `require` time and may well log for the
  -- first time from a libuv timer or a `vim.system` exit callback. Creating
  -- the crash-capture augroup there raises E5560, so the first record must not
  -- throw, must still reach every sink, and must still end up with the group,
  -- armed from the main loop.
  do
    pcall(vim.api.nvim_del_augroup_by_name, "lib_logger_fastarm")
    local ffile = H.tmpfile("-fast.jsonl")
    local fastlog = L.new({ name = "fastarm", notify_level = "off", file = ffile })
    local sunk = {}
    fastlog.add_sink(function(record)
      sunk[#sunk + 1] = record.msg
    end)

    local result
    local timer = assert(vim.uv.new_timer())
    timer:start(0, 0, function()
      timer:stop()
      timer:close()
      local in_fast = vim.in_fast_event()
      local ok_first, err_first = pcall(fastlog.info, "first from a timer")
      local ok_second, err_second = pcall(fastlog.info, "second from a timer")
      result = {
        in_fast = in_fast,
        ok_first = ok_first,
        err_first = err_first,
        ok_second = ok_second,
        err_second = err_second,
      }
    end)
    ok(
      vim.wait(2000, function()
        return result ~= nil
      end, 5),
      "the timer callback ran"
    )

    eq(result.in_fast, true, "the records were logged from a fast event")
    eq(
      result.ok_first,
      true,
      "the first record from a fast event does not throw: " .. tostring(result.err_first)
    )
    eq(
      result.ok_second,
      true,
      "the second record from a fast event does not throw: " .. tostring(result.err_second)
    )
    eq(sunk[1], "first from a timer", "the first record still reaches the extra sinks")
    eq(sunk[2], "second from a timer", "the second record reaches the extra sinks")
    eq(#fastlog.snapshot(), 2, "both records are in the ring")

    ok(
      vim.wait(2000, function()
        return pcall(vim.api.nvim_get_autocmds, { group = "lib_logger_fastarm" })
      end, 5),
      "crash capture is armed from the main loop afterwards"
    )
    -- Arming re-creates the group with `clear = true`, so the group holds one
    -- autocmd however often it was armed; only the autocmd id (new on every
    -- arming) tells a single arming from one per record.
    local fast_armed = vim.api.nvim_get_autocmds({ group = "lib_logger_fastarm" })
    eq(#fast_armed, 1, "armed exactly once")
    local fast_id = fast_armed[1].id

    fastlog.info("later, from the main loop")
    fastlog.info("and once more")
    local fast_again = vim.api.nvim_get_autocmds({ group = "lib_logger_fastarm" })
    eq(#fast_again, 1, "still one autocmd")
    eq(fast_again[1].id, fast_id, "no second arming: the records after it keep the same autocmd")
    pcall(vim.api.nvim_del_augroup_by_name, "lib_logger_fastarm")
  end

  -- ------------------------------------------------- a failed arming retries
  -- Arming runs under pcall and the pending flag only drops once it went
  -- through, so an arming that fails neither raises out of the record nor
  -- leaves the session without its VimLeavePre flush: the next record tries
  -- again. Creating the augroup is made to fail for the first record only.
  do
    local group = "lib_logger_armretry"
    pcall(vim.api.nvim_del_augroup_by_name, group)
    local rfile = H.tmpfile("-retry.jsonl")
    local armlog = L.new({ name = "armretry", notify_level = "off", file = rfile })

    local real_create_augroup = vim.api.nvim_create_augroup
    local attempts = 0
    vim.api.nvim_create_augroup = function()
      attempts = attempts + 1
      error("augroup refused")
    end
    local ok_first, err_first = pcall(armlog.info, "the arming fails on this one")
    vim.api.nvim_create_augroup = real_create_augroup

    eq(ok_first, true, "a failing arming does not raise out of the record: " .. tostring(err_first))
    eq(attempts, 1, "the first record tried to arm")
    eq(pcall(vim.api.nvim_get_autocmds, { group = group }), false, "nothing was armed")
    eq(#armlog.snapshot(), 1, "the record is in the ring all the same")
    eq(#H.read_lines(rfile), 1, "the record is in the file all the same")

    armlog.info("the next record retries")
    local has_group, retried = pcall(vim.api.nvim_get_autocmds, { group = group })
    ok(has_group, "the next record retried the arming that failed")
    eq(#retried, 1, "the next record armed crash capture")

    armlog.info("and then it is armed for good")
    local after = vim.api.nvim_get_autocmds({ group = group })
    eq(#after, 1, "still one autocmd")
    eq(after[1].id, retried[1].id, "no arming once the retry went through")
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end
end
