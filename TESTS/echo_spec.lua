-- TESTS/echo_spec.lua — lib.nvim.echo: nvim_echo delivery, history flag,
-- level-to-highlight mapping, and the fast-event reentry guard.

return function(H)
  local eq, ok = H.eq, H.ok
  local echo = require("lib.nvim.echo")

  local function capture(fn)
    local seen
    H.with_patched(vim.api, "nvim_echo", function(chunks, history, opts)
      seen = { chunks = chunks, history = history, opts = opts }
    end, fn)
    return seen
  end

  -- Default: history = false.
  local seen = capture(function()
    echo.write("hello")
  end)
  eq(seen.history, false, "history defaults to false")
  eq(seen.chunks[1][1], "hello", "plain string becomes a single chunk")
  eq(seen.chunks[1][2], nil, "no level: no highlight group")

  -- Explicit history = true.
  seen = capture(function()
    echo.write("done", { history = true })
  end)
  eq(seen.history, true, "history = true is forwarded to nvim_echo")

  -- Level-to-highlight mapping: only WARN/ERROR get a highlight.
  seen = capture(function()
    echo.write("info line", { level = vim.log.levels.INFO })
  end)
  eq(seen.chunks[1][2], nil, "INFO gets no highlight")

  seen = capture(function()
    echo.write("careful", { level = vim.log.levels.WARN })
  end)
  eq(seen.chunks[1][2], "WarningMsg", "WARN maps to WarningMsg")

  seen = capture(function()
    echo.write("broken", { level = vim.log.levels.ERROR })
  end)
  eq(seen.chunks[1][2], "ErrorMsg", "ERROR maps to ErrorMsg")

  -- Chunk list passed through unmodified.
  seen = capture(function()
    echo.write({ { "a", "Comment" }, { "b" } })
  end)
  eq(#seen.chunks, 2, "a chunk list is passed through as-is")
  eq(seen.chunks[1][2], "Comment", "existing per-chunk highlight is preserved")

  -- Called from a fast event: rescheduled instead of erroring.
  local calls = 0
  H.with_patched(vim.api, "nvim_echo", function()
    calls = calls + 1
  end, function()
    vim.uv.new_timer():start(0, 0, function()
      echo.write("from a timer")
    end)
    vim.wait(200, function()
      return calls > 0
    end)
    ok(calls > 0, "a write from a fast event lands on the main loop")
  end)
end
