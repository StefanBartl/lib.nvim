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

  -- ----------------------------------------------------------------- rtrim
  local rtrim = require("lib.lua.strings.core").rtrim
  eq(rtrim("  x  "), "  x", "rtrim keeps the indentation")
  eq(rtrim("   "), "", "rtrim of blanks is empty")
  eq(rtrim(nil), "", "rtrim of a non-string is empty")
  local ms_r = elapsed_ms(function()
    ok(#rtrim("a" .. (" "):rep(40000) .. "b") > 0, "rtrim inner run")
    ok(#rtrim((" "):rep(40000)) == 0, "rtrim blank run")
  end)
  ok(ms_r < 500, ("rtrim took %.0f ms"):format(ms_r))

  -- --------------------------------------------- callers that used to be quadratic
  local run = (" "):rep(40000)
  local loc = require("lib.lua.strings.location").parse_location
  eq(loc("  a.lua:3:4  ").path, "a.lua", "parse_location still trims")
  -- "path +line": same answers as the old `^(.-)%s+%+(%d+)$`
  eq(loc("a.lua +12").path, "a.lua", "path +line")
  eq(loc("a.lua +12").line, 12, "path +line: line")
  eq(loc("a b.lua    +3").path, "a b.lua", "the whole whitespace run before + is dropped")
  eq(loc("a.lua+12"), nil, "no whitespace before +: not a location")
  eq(loc("+12"), nil, "only +line: not a location")
  eq(loc("a.lua +x"), nil, "+ without digits")
  -- the later patterns of the function are the ones that went quadratic, so aim at them
  local ms_l = elapsed_ms(function()
    eq(loc("a" .. run .. "b"), nil, "no match")
    eq(loc("a" .. run .. "+b"), nil, "+ without digits")
    eq(loc("a" .. run .. "+7").line, 7, "run, then +7")
    loc("a" .. run .. "b:1")
  end)
  ok(ms_l < 500, ("parse_location took %.0f ms"):format(ms_l))

  -- markdown.table.parse_row: same cells as before, linear on a long run
  local row = require("lib.nvim.markdown.table").parse_row
  eq(table.concat(row("| a | b  |"), ","), "a,b", "cells are trimmed")
  eq(table.concat(row("  | a |  |  "), ","), "a,", "an empty cell stays")
  eq(#row("||"), 1, "empty row has one empty cell")
  eq(#row("|"), 0, "a lone pipe is no row")
  eq(#row("a | b"), 0, "no outer pipes: no row")
  local ms_t = elapsed_ms(function()
    eq(row("|a" .. run .. "b|")[1], "a" .. run .. "b", "inner run kept")
    eq(#row("|a" .. run .. "b"), 0, "no closing pipe")
    eq(row("|x" .. run .. "|")[1], "x", "trailing run before the closing pipe")
  end)
  ok(ms_t < 500, ("parse_row took %.0f ms"):format(ms_t))
end
