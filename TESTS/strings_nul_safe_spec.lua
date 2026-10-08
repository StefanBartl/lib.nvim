-- TESTS/strings_nul_safe_spec.lua — lib.lua.strings.core.nul_safe (and its aggregator alias)
--
-- A NUL in a Lua string reaches `vim.fn` as a Blob, and `strdisplaywidth()`, `strchars()`,
-- `strcharpart()` and `split()` raise E976 on it. `nul_safe` swaps each NUL for an SOH, which is
-- one byte, one character and two display cells -- exactly what a NUL is drawn as (`^@`) -- so
-- a caller measures the swapped copy and keeps the original.

return function(H)
  local eq, ok = H.eq, H.ok
  local core = require("lib.lua.strings.core")
  local nul = string.char(0)

  for label, nul_safe in pairs({
    core = core.nul_safe,
    aggregator = require("lib.lua.strings").nul_safe,
  }) do
    eq(nul_safe("abc"), "abc", label .. ": a string without a NUL comes back as it is")
    eq(nul_safe(""), "", label .. ": empty stays empty")
    eq(nul_safe("a" .. nul .. "b"), "a\1b", label .. ": a NUL becomes an SOH")
    eq(nul_safe(nul), "\1", label .. ": a lone NUL")
    eq(nul_safe(nul .. nul .. "x" .. nul), "\1\1x\1", label .. ": every NUL, not the first only")
    eq(nul_safe("é" .. nul .. "漢"), "é\1漢", label .. ": the bytes around it are left alone")
    eq(#nul_safe("a" .. nul .. "b"), 3, label .. ": one byte for one byte")
    eq(nul_safe(nil), nil, label .. ": nil is not a string")
    eq(nul_safe(42), 42, label .. ": a number is not a string")
    local t = {}
    eq(nul_safe(t), t, label .. ": a table is handed back as it is")
  end

  -- The premise, and what the swap buys: the measure that raised now answers, and says what
  -- the NUL is drawn as.
  local raised = not pcall(vim.fn.strdisplaywidth, "a" .. nul .. "b")
  ok(raised, "strdisplaywidth() raises on a NUL in a Lua string (E976)")
  local swapped = core.nul_safe("a" .. nul .. "b")
  eq(vim.fn.strdisplaywidth(swapped), 4, "a NUL is two cells wide, like the ^@ it is drawn as")
  eq(vim.fn.strchars(swapped), 3, "and one character")
  eq(vim.fn.strcharpart(swapped, 1, 1), "\1", "strcharpart() takes it apart")
  eq(#vim.fn.split(swapped, "\\zs"), 3, "so does split()")

  -- Linear: a long line of NULs is one pass, not a retry per byte.
  local long = string.rep(nul, 200000)
  local t0 = vim.uv.hrtime()
  local out = core.nul_safe(long)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  eq(#out, 200000, "a long line keeps its length")
  ok(out:find(nul, 1, true) == nil, "and holds no NUL")
  ok(ms < 1000, ("200 000 NULs took %.0f ms"):format(ms))
end
