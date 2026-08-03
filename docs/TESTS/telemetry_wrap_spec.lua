-- docs/TESTS/telemetry_wrap_spec.lua — lib.strategies.telemetry_wrap
--
-- The one piece of the old lib.nvim.telemetry test suite that could not move
-- with the rest of it to runtime-analysis.nvim: this specifically exercises
-- `require("lib")`'s own metatable-hidden aggregate, which only exists here.
-- Covers the round-trip this module exists for: `control.keys()` enumerating
-- the aggregate despite the metatable, `wrap()`/`start()` installing real
-- dispatchers over real lib.nvim functions, a real call being counted, and
-- `stop()` + `unwrap()` restoring the aggregate byte-for-byte -- the same
-- identity-restore property every other telemetry test asserts, just against
-- `require("lib")` specifically instead of a plain table.

return function(H)
  local telemetry = require("runtime-analysis.telemetry")
  local telemetry_wrap = require("lib.strategies.telemetry_wrap")
  local control = require("lib.strategies.control")
  local lib = require("lib")

  local original_trim = lib.trim

  local t = telemetry.new({ namespace = "spec.telemetry_wrap", persist = false })

  local n = telemetry_wrap.wrap(t)
  H.ok(n > 20, "the whole aggregate gets registered, not just one function")
  H.eq(lib.trim, original_trim, "wrap() alone installs nothing, same as inst.wrap()")

  local keys = control.keys(lib)
  local has_trim = false
  for _, k in ipairs(keys) do
    if k == "trim" then
      has_trim = true
    end
  end
  H.ok(has_trim, "special-handler keys included, not just MODULE_MAP")

  t.start()
  H.ok(
    lib.trim ~= original_trim,
    'start() installs the wrapper over the real require("lib") aggregate'
  )
  H.eq(lib.trim("  x  "), "x", "the wrapper is transparent -- a real call still behaves correctly")

  local found = nil
  for _, e in ipairs(t.report().entries) do
    if e.key == "trim" then
      found = e
    end
  end
  H.ok(found ~= nil, 'the real call through require("lib") was counted')
  H.eq(found.calls, 1, "exactly once")

  t.stop()
  H.eq(lib.trim, original_trim, "stop() restores the original object exactly")
  t.unwrap()

  telemetry_wrap.unwrap()
  H.eq(rawget(lib, "trim"), nil, "unwrap() removes the rawset materialization")
  H.eq(
    lib.trim,
    original_trim,
    "...and the metatable still resolves it to the same function afterward"
  )
end
