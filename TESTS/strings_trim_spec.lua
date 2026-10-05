-- TESTS/strings_trim_spec.lua — lib.lua.strings.core.trim (and the normalize.utils alias)
--
-- The old `gsub("%s+$", "")` retried the rest of a whitespace run from every byte inside
-- it: 40 000 spaces in the middle of a value cost seconds (SEC-32). The bound below is
-- generous for a linear walk (a few ms) and far below the quadratic cost, so it does not
-- flake on a slow machine.

return function(H)
  local eq, ok = H.eq, H.ok
  local trim = require("lib.lua.strings.core").trim
  local alias = require("lib.nvim.normalize.utils").trim

  -- ------------------------------------------------------------- semantics
  for _, fn in ipairs({ trim, alias }) do
    eq(fn("  x  "), "x", "both sides are stripped")
    eq(fn("x"), "x", "nothing to strip")
    eq(fn(""), "", "empty stays empty")
    eq(fn("   "), "", "only whitespace gives empty")
    eq(fn(" \t\r\n a b \t\r\n "), "a b", "every kind of ASCII whitespace, inner kept")
    eq(fn("a   b"), "a   b", "an inner run is not touched")
    eq(fn("  a"), "a", "leading only")
    eq(fn("a  "), "a", "trailing only")
    eq(fn("\194\160x"), "\194\160x", "a UTF-8 no-break space is not ASCII whitespace")
    eq(fn(nil), "", "non-string input trims to empty")
    eq(fn(42), "", "a number is not a string")
  end

  -- ----------------------------------------------------------- linear time
  local function elapsed_ms(fn)
    local t0 = vim.uv.hrtime()
    fn()
    return (vim.uv.hrtime() - t0) / 1e6
  end

  local inner = "a" .. (" "):rep(40000) .. "b"
  local blank = (" "):rep(40000)
  local lead = (" "):rep(40000) .. "x"
  local trail = "x" .. (" "):rep(40000)
  local both = lead .. (" "):rep(40000) .. "y" .. (" "):rep(40000)

  eq(trim(inner), inner, "an inner run of 40 000 spaces survives")
  eq(trim(blank), "", "40 000 blanks")
  eq(trim(lead), "x", "40 000 leading blanks")
  eq(trim(trail), "x", "40 000 trailing blanks")
  eq(trim(both), "x" .. (" "):rep(40000) .. "y", "runs on both sides and in the middle")

  for label, s in pairs({ inner = inner, blank = blank, lead = lead, trail = trail, both = both }) do
    local ms = elapsed_ms(function()
      for _ = 1, 5 do
        ok(#trim(s) >= 0 and #alias(s) >= 0, "trim returns a string")
      end
    end)
    ok(ms < 500, ("trim of the %s case took %.0f ms (linear time expected)"):format(label, ms))
  end
end
