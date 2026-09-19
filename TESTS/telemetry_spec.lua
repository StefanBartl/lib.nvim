-- TESTS/telemetry_spec.lua — lib.nvim.telemetry
--
-- Two things worth pinning on `M.new()`'s option handling (ERR-50 / ERR-22):
--
--   * A typo'd option key (`flush_interval` for `flush_interval_ms`) must be
--     reported with a "did you mean" hint, the same contract `lib.config`
--     already gives `setup()` — not silently merged away.
--   * An invalid VALUE for a restricted numeric field (`retention_days`,
--     `flush_interval_ms`, `max_arg_values`) must degrade to that field's
--     documented default rather than reach the first `<`/`<=` comparison
--     downstream and crash — which used to happen inside `store.prune`
--     (the flush timer), `start_timer` (`t.start()` itself) and `_record`
--     (synchronously, inside the very next profiled call) respectively.
--     `flush_interval_ms = 0` ("disabled", documented) and a numeric string
--     like `max_arg_values = "32"` must both keep working exactly as before.

return function(H)
  local eq, ok = H.eq, H.ok
  local telemetry = require("lib.nvim.telemetry")

  local warnings = {}
  local real_notify = vim.notify
  vim.notify = function(msg, level)
    warnings[#warnings + 1] = { msg = msg, level = level }
  end

  -- ---------------------------------------------------------------------
  -- ERR-50: unknown option keys
  -- ---------------------------------------------------------------------

  warnings = {}
  ---@type any
  local typo_inst = telemetry.new({ namespace = "TESTS.telemetry.err50", flush_interval = 5000 })
  eq(#warnings, 1, "telemetry.new: a typo'd key is reported once")
  ok(
    warnings[1] ~= nil
      and warnings[1].msg:find("flush_interval", 1, true) ~= nil
      and warnings[1].msg:find("did you mean flush_interval_ms", 1, true) ~= nil,
    "telemetry.new: the report names the key and the nearest known one: "
      .. tostring(warnings[1] and warnings[1].msg)
  )
  eq(warnings[1].level, vim.log.levels.WARN, "telemetry.new: reported as a warning")
  -- The typo'd field never reached cfg; flush_interval_ms kept its default
  -- (60000), so starting the instance must not blow up on a stray string.
  ok(typo_inst ~= nil, "telemetry.new: still returns a usable instance despite the typo")

  warnings = {}
  telemetry.new({
    namespace = "TESTS.telemetry.err50.known",
    dir = H.tmpfile(),
    retention_days = 7,
    flush_interval_ms = 0,
    max_arg_values = 10,
    persist = false,
    remind_after = false,
  })
  eq(#warnings, 0, "telemetry.new: every documented key together reports nothing")

  -- ---------------------------------------------------------------------
  -- ERR-22: invalid numeric VALUES degrade instead of crashing
  -- ---------------------------------------------------------------------

  warnings = {}
  local dir_a = H.tmpfile()
  ---@type any
  local t_retention = telemetry.new({
    namespace = "TESTS.telemetry.err22.retention",
    retention_days = "30d", -- typo'd type, not the "7d"-style duration `report{since=}` accepts
    persist = true,
    dir = dir_a,
  })
  local ok_flush, err_flush = pcall(t_retention.flush)
  ok(
    ok_flush,
    "telemetry: flush() with a non-numeric retention_days does not crash: " .. tostring(err_flush)
  )
  ok(
    #warnings >= 1 and warnings[1].msg:find("retention_days", 1, true) ~= nil,
    "telemetry: the invalid retention_days is reported"
  )
  vim.fn.delete(dir_a, "rf")

  warnings = {}
  local dir_b = H.tmpfile()
  ---@type any
  local t_flush = telemetry.new({
    namespace = "TESTS.telemetry.err22.flush",
    flush_interval_ms = "60s",
    persist = true,
    dir = dir_b,
  })
  local ok_start, err_start = pcall(t_flush.start)
  ok(
    ok_start,
    "telemetry: start() with a non-numeric flush_interval_ms does not crash: "
      .. tostring(err_start)
  )
  t_flush.stop()
  ok(
    #warnings >= 1 and warnings[1].msg:find("flush_interval_ms", 1, true) ~= nil,
    "telemetry: the invalid flush_interval_ms is reported"
  )
  vim.fn.delete(dir_b, "rf")

  -- flush_interval_ms = 0 keeps meaning "disabled" (documented), not "invalid".
  warnings = {}
  local dir_c = H.tmpfile()
  local t_disabled = telemetry.new({
    namespace = "TESTS.telemetry.err22.disabled",
    flush_interval_ms = 0,
    persist = true,
    dir = dir_c,
  })
  t_disabled.start()
  eq(#warnings, 0, "telemetry: flush_interval_ms = 0 is not reported as invalid")
  t_disabled.stop()
  vim.fn.delete(dir_c, "rf")

  warnings = {}
  ---@type any
  local t_args = telemetry.new({
    namespace = "TESTS.telemetry.err22.args",
    max_arg_values = "not-a-number",
    persist = false,
  })
  local target = {
    fn = function(a)
      return a
    end,
  }
  t_args.wrap(target, "t")
  t_args.start({ profile_args = true })
  local ok_call, err_call = pcall(target.fn, 1)
  ok(
    ok_call,
    "telemetry: a profiled call with a non-numeric max_arg_values does not crash: "
      .. tostring(err_call)
  )
  t_args.stop()
  ok(
    #warnings >= 1 and warnings[1].msg:find("max_arg_values", 1, true) ~= nil,
    "telemetry: the invalid max_arg_values is reported"
  )

  -- A numeric STRING (as opposed to a non-numeric one) still coerces cleanly,
  -- same as `tonumber` everywhere else in this codebase (Ring.new, etc.).
  warnings = {}
  ---@type any
  local t_numstr = telemetry.new({
    namespace = "TESTS.telemetry.err22.numstring",
    max_arg_values = "32",
    persist = false,
  })
  local target2 = {
    fn = function(a)
      return a
    end,
  }
  t_numstr.wrap(target2, "t")
  t_numstr.start({ profile_args = true })
  local ok_call2, err_call2 = pcall(target2.fn, 1)
  ok(ok_call2, "telemetry: a numeric-string max_arg_values does not crash: " .. tostring(err_call2))
  eq(#warnings, 0, "telemetry: a numeric string is coerced, not reported as invalid")
  t_numstr.stop()

  vim.notify = real_notify
end
