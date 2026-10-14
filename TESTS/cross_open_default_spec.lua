-- TESTS/cross_open_default_spec.lua -- cross.open_default: which launcher a URL and a path get on
-- Windows. A URL must go to rundll32 url.dll,FileProtocolHandler (ShellExecute in-process): given
-- a URL with `?`, `&` or a `%xx` escape, explorer.exe opens the Documents folder in a hidden
-- window instead of the browser and exits 1 as on success (measured 2026-10-14).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  local run = require("lib.nvim.cross.run")
  local real_detached = run.run_detached
  local saved = {}
  for _, name in ipairs({ "is_windows", "is_wsl", "is_macos" }) do
    saved[name] = package.loaded["lib.nvim.cross.platform." .. name]
  end
  package.loaded["lib.nvim.cross.platform.is_windows"] = function()
    return true
  end
  package.loaded["lib.nvim.cross.platform.is_wsl"] = function()
    return false
  end
  package.loaded["lib.nvim.cross.platform.is_macos"] = function()
    return false
  end

  local captured
  run.run_detached = function(argv)
    captured = argv
    return true
  end

  local okrun, err = pcall(function()
    local open_default = require("lib.nvim.cross.open_default")
    local URL = "https://example.com/a?b=1&c=%3F"

    ok(open_default(URL), "a URL is dispatched")
    eq(captured[1], "rundll32.exe", "windows: a URL goes to rundll32")
    eq(captured[2], "url.dll,FileProtocolHandler", "through the ShellExecute entry point")
    eq(captured[3], URL, "with the URL untouched: ?, & and %xx survive")
    eq(#captured, 3, "and nothing else")

    ok(open_default("www.example.com/x?y=1"), "a www. target is a URL too")
    eq(captured[1], "rundll32.exe", "and also goes to rundll32")

    ok(open_default("C:/tmp/some file.pdf"), "a path is dispatched")
    eq(captured[1], "explorer.exe", "windows: a file path keeps explorer.exe")
    ok(not captured[2]:find("/", 1, true), "absolute and backslashed")
    eq(#captured, 2, "two elements")

    -- WSL: a URL still goes to rundll32
    package.loaded["lib.nvim.cross.platform.is_wsl"] = function()
      return true
    end
    ok(open_default(URL), "wsl: a URL is dispatched")
    eq(captured[1], "rundll32.exe", "wsl: a URL goes to rundll32")
    eq(captured[3], URL, "untouched")
  end)

  run.run_detached = real_detached
  for name, mod in pairs(saved) do
    package.loaded["lib.nvim.cross.platform." .. name] = mod
  end
  if not okrun then
    error(err, 0)
  end
end
