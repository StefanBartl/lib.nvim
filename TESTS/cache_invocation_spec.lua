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

  -- the live selection by mode: visual, linewise, blockwise and the select-mode twins; never from stale marks
  local function selection_in(mode, vmark, cursor)
    local text
    H.with_patched(vim.fn, "mode", function()
      return mode
    end, function()
      H.with_patched(vim.fn, "getpos", function(mark)
        return mark == "v" and vmark or cursor
      end, function()
        text = invocation.read_editor_state().selection
      end)
    end)
    return text
  end
  local v_from, v_to = { 0, 1, 1, 0 }, { 0, 2, 3, 0 }
  eq(selection_in("v", v_from, v_to), "alpha beta\ngam", "selection: charwise")
  eq(selection_in("V", v_from, v_to), "alpha beta\ngamma", "selection: linewise takes whole lines")
  eq(
    selection_in(string.char(22), { 0, 1, 2, 0 }, v_to),
    "lp\nam",
    "selection: blockwise takes the block"
  )
  eq(selection_in("s", v_from, v_to), "alpha beta\ngam", "selection: select mode (charwise)")
  eq(selection_in("S", v_from, v_to), "alpha beta\ngamma", "selection: select mode (linewise)")
  eq(
    selection_in(string.char(19), { 0, 1, 2, 0 }, v_to),
    "lp\nam",
    "selection: select mode (blockwise)"
  )
  eq(selection_in("n", v_from, v_to), nil, "selection: none in normal mode, whatever the marks say")

  -- two scopes with the same name are still two scopes
  local twin_a, twin_b = invocation.new("twin"), invocation.new("twin")
  local twin_calls = 0
  twin_a:run(function()
    twin_a:memo("k", function()
      return "A"
    end)
    twin_b:run(function()
      eq(
        twin_b:memo("k", function()
          twin_calls = twin_calls + 1
          return "B"
        end),
        "B",
        "same-name scopes: the second one has its own value"
      )
    end)
    eq(
      twin_a:memo("k", function()
        twin_calls = twin_calls + 100
        return "A2"
      end),
      "A",
      "same-name scopes: the end of the other run does not wipe this one's values"
    )
  end)
  eq(twin_calls, 1, "same-name scopes: each producer ran as expected")

  -- a run belongs to its coroutine: a yield in the middle neither leaks values nor blocks the cleanup
  local co_scope = invocation.new("co")
  local co = coroutine.create(function()
    co_scope:run(function()
      co_scope:memo("x", function()
        return "inside"
      end)
      coroutine.yield()
    end)
  end)
  coroutine.resume(co)
  eq(co_scope:active(), false, "coroutine: the main thread is not inside the suspended run")
  eq(
    co_scope:memo("x", function()
      return "main"
    end),
    "main",
    "coroutine: the suspended run's values are not visible outside it"
  )
  local main_calls = 0
  for _ = 1, 2 do
    co_scope:run(function()
      co_scope:memo("x", function()
        main_calls = main_calls + 1
        return "m"
      end)
    end)
  end
  eq(
    main_calls,
    2,
    "coroutine: a run on the main thread still starts empty and cleans up afterwards"
  )
  coroutine.resume(co)
  eq(coroutine.status(co), "dead", "coroutine: the suspended run finishes normally")

  -- memory's BufWritePost auto-invalidation clears namespaces; a run must survive it
  local memory = require("lib.nvim.cache.memory")
  memory.setup_auto_invalidation()
  local inv_calls = 0
  scope:run(function()
    for _ = 1, 2 do
      scope:memo("w", function()
        inv_calls = inv_calls + 1
        return 1
      end)
      vim.api.nvim_exec_autocmds("BufWritePost", {})
    end
  end)
  memory.disable_auto_invalidation()
  eq(inv_calls, 1, "a BufWritePost mid-run does not clear the run's values")

  -- keys: only strings; the editor-state slot cannot be hijacked
  ok(not pcall(scope.memo, scope, 5, function() end), "memo: a non-string key is refused")
  scope:run(function()
    scope:memo("editor_state", function()
      return "not a state"
    end)
    eq(
      type(scope:editor_state()),
      "table",
      "memo: the key 'editor_state' does not collide with the reading"
    )
  end)

  vim.api.nvim_buf_delete(buf, { force = true })
end
