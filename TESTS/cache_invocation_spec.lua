-- TESTS/cache_invocation_spec.lua — lib.nvim.cache.invocation (per-call cache, editor-state reader)

return function(H)
  local eq, ok = H.eq, H.ok
  local invocation = require("lib.nvim.cache.invocation")

  local scope = invocation.new("spec_a")
  local calls = 0
  local function produce()
    calls = calls + 1
    return { n = calls }
  end

  -- outside a run nothing is remembered
  eq(scope:active(), false, "invocation: not active outside run")
  local first = scope:memo("k", produce)
  local second = scope:memo("k", produce)
  eq(calls, 2, "invocation: outside run the producer is called through")
  ok(first ~= second, "invocation: outside run nothing is shared")

  -- inside a run: once; nested runs share; the outermost end drops the values
  calls = 0
  local ret_a, ret_b = scope:run(function(x)
    eq(scope:active(), true, "invocation: active inside run")
    local a = scope:memo("k", produce)
    local b
    scope:run(function()
      b = scope:memo("k", produce)
    end)
    ok(a == b, "invocation: a nested run shares the outer values")
    eq(scope:memo("k", produce), a, "invocation: second read inside the run is the same value")
    return x, a.n
  end, "arg")
  eq(calls, 1, "invocation: the producer ran once per run")
  eq(ret_a, "arg", "invocation: run passes arguments through")
  eq(ret_b, 1, "invocation: run returns the function's results")
  eq(scope:active(), false, "invocation: inactive again after run")
  scope:run(function()
    scope:memo("k", produce)
  end)
  eq(calls, 2, "invocation: a new run starts empty")

  -- nil and false are remembered
  local nil_calls = 0
  scope:run(function()
    for _ = 1, 3 do
      scope:memo("nothing", function()
        nil_calls = nil_calls + 1
        return nil
      end)
      scope:memo("no", function()
        nil_calls = nil_calls + 1
        return false
      end)
    end
  end)
  eq(nil_calls, 2, "invocation: nil and false results are cached too")

  -- an error: re-raised unchanged, the cache is cleaned, the depth restored
  local good, err = pcall(function()
    scope:run(function()
      scope:memo("k", produce)
      error("boom", 0)
    end)
  end)
  eq(good, false, "invocation: run re-raises")
  eq(err, "boom", "invocation: the error is unchanged (no position stamp)")
  eq(scope:active(), false, "invocation: inactive after a raising run")
  calls = 0
  scope:run(function()
    scope:memo("k", produce)
  end)
  eq(calls, 1, "invocation: nothing leaked from the raising run")

  -- a raising producer stores nothing
  local tries = 0
  scope:run(function()
    for _ = 1, 2 do
      pcall(scope.memo, scope, "flaky", function()
        tries = tries + 1
        error("no", 0)
      end)
    end
  end)
  eq(tries, 2, "invocation: a raising producer is not cached")

  -- scopes are independent
  local other = invocation.new("spec_b")
  local cross = 0
  scope:run(function()
    scope:memo("shared", function()
      return 1
    end)
    other:run(function()
      other:memo("shared", function()
        cross = cross + 1
        return 2
      end)
    end)
  end)
  eq(cross, 1, "invocation: two scopes do not share values")

  -- editor state
  vim.cmd("silent! only")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha beta", "gamma" })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  local live = invocation.read_editor_state()
  eq(live.buf, buf, "editor_state: buffer")
  ok(vim.deep_equal(live.cursor, { 1, 2 }), "editor_state: cursor")
  eq(live.cword, "alpha", "editor_state: <cWORD>")
  eq(live.selection, nil, "editor_state: no selection outside visual mode")
  eq(live.buffer_path, nil, "editor_state: an unnamed buffer has no path")

  local pinned
  scope:run(function()
    pinned = scope:editor_state()
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local again = scope:editor_state()
    ok(again == pinned, "editor_state: one reading per run")
    ok(vim.deep_equal(again.cursor, { 1, 2 }), "editor_state: the cursor of the first reading")
  end)
  ok(
    vim.deep_equal(scope:editor_state().cursor, { 1, 7 }),
    "editor_state: outside a run every call reads afresh"
  )
  eq(scope:editor_state().cword, "beta", "editor_state: and sees the new cursor position")

  -- a live visual selection (mode and positions stubbed: a script cannot stay in visual mode)
  H.with_patched(vim.fn, "mode", function()
    return "v"
  end, function()
    H.with_patched(vim.fn, "getpos", function(mark)
      return mark == "v" and { 0, 1, 1, 0 } or { 0, 2, 3, 0 }
    end, function()
      local sel = invocation.read_editor_state()
      eq(sel.selection, "alpha beta\ngam", "editor_state: the live visual selection")
    end)
  end)

  vim.api.nvim_buf_delete(buf, { force = true })
end
