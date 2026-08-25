-- TESTS/wslpath_spec.lua — lib.nvim.cross.fs.wslpath
--
-- The conversions themselves can only be verified inside a real WSL session,
-- so the portable contract this spec pins down is the one every caller relies
-- on off-WSL: never raise, always answer nil. That is what makes an
-- unconditional `wslpath.to_win(p)` safe on native Windows/macOS/Linux.

return function(H)
  local eq, ok = H.eq, H.ok

  local wslpath = require("lib.nvim.cross.fs.wslpath")

  -- --------------------------------------------------------------- surface

  eq(type(wslpath.to_win), "function", "wslpath: to_win is exported")
  eq(type(wslpath.to_unix), "function", "wslpath: to_unix is exported")

  eq(
    require("lib.nvim.cross").fs.wslpath,
    wslpath,
    "wslpath: reachable as lib.nvim.cross.fs.wslpath"
  )

  -- ------------------------------------------------------- invalid input

  -- Guarded before the spawn, so these hold on every platform including WSL.
  for _, bad in ipairs({ "", nil, 42, {} }) do
    local label = type(bad) == "string" and "empty string" or type(bad)
    eq(wslpath.to_win(bad), nil, ("wslpath: to_win(%s) is nil, not an error"):format(label))
    eq(wslpath.to_unix(bad), nil, ("wslpath: to_unix(%s) is nil, not an error"):format(label))
  end

  -- ------------------------------------------------------ platform contract

  -- A well-formed path: the result is genuinely platform-dependent, so assert
  -- the type contract (string|nil) rather than a value. Off WSL the `wslpath`
  -- binary is absent and run_blocking_captured reports failure -> nil; inside
  -- WSL a /mnt/c path converts to a C:\ path.
  local win = wslpath.to_win("/mnt/c/Users")
  ok(
    win == nil or type(win) == "string",
    "wslpath: to_win returns string|nil for a well-formed path"
  )

  local unix = wslpath.to_unix([[C:\Users]])
  ok(
    unix == nil or type(unix) == "string",
    "wslpath: to_unix returns string|nil for a well-formed path"
  )

  -- Whatever comes back must already be trimmed — a stray newline would
  -- corrupt the very next argv the caller builds out of it.
  if type(win) == "string" then
    eq(win:match("[\r\n]"), nil, "wslpath: converted path carries no line breaks")
  end
end
