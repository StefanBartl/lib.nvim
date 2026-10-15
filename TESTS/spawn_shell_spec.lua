-- TESTS/spawn_shell_spec.lua — cross.uv.spawn_command / spawn_shell_command: the process handle is closed before
-- the user's on_exit runs, and on_exit is delivered on the main loop (a vim.api call there must not raise E5560).

return function(H)
  local eq, ok = H.eq, H.ok
  local exit_cmd = "exit 0"

  local function run(name, start)
    local seen
    local handle = start(function(code)
      seen = {
        code = code,
        fast = vim.in_fast_event(),
        closing = nil,
        -- A `vim.api` call that raises in the fast event context.
        api_ok = pcall(vim.api.nvim_get_current_buf),
      }
    end)
    ok(handle ~= nil, name .. ": returns the process handle")
    ok(
      vim.wait(5000, function()
        return seen ~= nil
      end, 10),
      name .. ": on_exit is called"
    )
    if seen then
      seen.closing = handle:is_closing()
      eq(seen.code, 0, name .. ": exit code is passed on")
      eq(seen.fast, false, name .. ": on_exit runs outside the fast event context")
      eq(seen.api_ok, true, name .. ": on_exit may call vim.api")
      eq(seen.closing, true, name .. ": the process handle is closed when on_exit runs")
    end
  end

  run("spawn_command", function(on_exit)
    return require("lib.nvim.cross.uv.spawn_command").spawn_project_command(exit_cmd, {
      stdio = { nil, nil, nil },
      on_exit = on_exit,
    })
  end)

  run("spawn_shell_command", function(on_exit)
    return require("lib.nvim.cross.uv.spawn_shell_command")(exit_cmd, {}, {
      stdio = { nil, nil, nil },
      on_exit = on_exit,
    })
  end)
end
