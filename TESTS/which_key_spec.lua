-- TESTS/which_key_spec.lua — lib.nvim.bindings.keymap.which_key
--
-- Group labels must not load which-key: under a lazy manager `require` IS the
-- load trigger, and the labels are sent during startup. They are queued until
-- which-key is loaded, then delivered.

return function(H)
  local eq, ok = H.eq, H.ok

  local saved_loaded = package.loaded["which-key"]
  local saved_preload = package.preload["which-key"]

  ---@return table wk module under test, fresh state
  local function fresh()
    package.loaded["lib.nvim.bindings.keymap.which_key"] = nil
    pcall(vim.api.nvim_del_augroup_by_name, "lib.nvim.which_key.pending")
    return require("lib.nvim.bindings.keymap.which_key")
  end

  local function restore()
    package.loaded["which-key"] = saved_loaded
    package.preload["which-key"] = saved_preload
    pcall(vim.api.nvim_del_augroup_by_name, "lib.nvim.which_key.pending")
  end

  -- The whole body runs in one `pcall`: it patches package.loaded/preload for
  -- "which-key" throughout, and TESTS/run.lua loads every spec into one shared
  -- Neovim instance -- a raised assertion that skipped `restore()` below would
  -- leak the stub into every later spec instead of just failing this one.
  local body_ok, body_err = pcall(function()
    -- ------------------------------------------- not loaded: queued, not required
    local loads = 0
    package.loaded["which-key"] = nil
    package.preload["which-key"] = function()
      loads = loads + 1
      return { add = function() end }
    end

    local wk = fresh()
    local applied = wk.add_group({ prefix = "<leader>x", group = "X things" })
    eq(applied, false, "add_group: not applied while which-key is not loaded")
    eq(loads, 0, "add_group: never requires which-key (that would load the plugin)")
    eq(wk.pending_count(), 1, "add_group: the label is queued")
    eq(wk.flush(), false, "flush: nothing to deliver to while which-key is not loaded")
    eq(wk.pending_count(), 1, "flush: ... and the queue is kept")

    -- a second, list-shaped call queues separately
    wk.add_group({
      { prefix = "<leader>y", group = "Y" },
      { prefix = "<leader>z", group = "Z" },
    })
    eq(wk.pending_count(), 2, "add_group: another call queues another list")

    -- ------------------------------------------ loaded later: delivered on the event
    local received = {}
    package.loaded["which-key"] = {
      add = function(entries)
        received[#received + 1] = entries
      end,
    }
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "which-key.nvim" })
    eq(wk.pending_count(), 0, "User LazyLoad: the queue is delivered once which-key is there")
    eq(#received, 2, "User LazyLoad: one add() per queued list")
    eq(received[1][1][1], "<leader>x", "User LazyLoad: entries arrive intact, in order")
    eq(received[1][1].group, "X things", "User LazyLoad: ... with their group label")
    eq(#received[2], 2, "User LazyLoad: a list-shaped call arrives as one list of two")

    -- the watcher removes itself after delivering
    local before = #received
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "anything" })
    eq(#received, before, "User LazyLoad: a second event delivers nothing twice")

    -- ------------------------------------- loaded already: applied immediately
    wk = fresh()
    received = {}
    local now_applied = wk.add_group({ prefix = "<leader>q", group = "Q" })
    eq(now_applied, true, "add_group: applied at once when which-key is loaded")
    eq(#received, 1, "add_group: exactly one add()")
    eq(wk.pending_count(), 0, "add_group: nothing queued")

    -- --------------------------------------- an unrelated User event does nothing
    package.loaded["which-key"] = nil
    wk = fresh()
    wk.add_group({ prefix = "<leader>u", group = "U" })
    package.loaded["which-key"] = { add = function() end }
    vim.api.nvim_exec_autocmds("User", { pattern = "SomethingElse" })
    eq(wk.pending_count(), 1, "an unrelated User event does not deliver")
    eq(wk.flush(), true, "flush: delivers by hand once which-key is loaded")
    eq(wk.pending_count(), 0, "flush: empties the queue")

    -- ------------------------------------ VimEnter delivers for an eager manager
    package.loaded["which-key"] = nil
    wk = fresh()
    wk.add_group({ prefix = "<leader>v", group = "V" })
    local seen = 0
    package.loaded["which-key"] = {
      add = function()
        seen = seen + 1
      end,
    }
    vim.api.nvim_exec_autocmds("VimEnter", {})
    eq(seen, 1, "VimEnter: delivers when which-key was loaded without an event")

    -- ------------------------------------------- when_loaded: for callers with
    -- their own way of talking to which-key
    package.loaded["which-key"] = nil
    wk = fresh()
    local got_mod
    eq(
      wk.when_loaded(function(mod)
        got_mod = mod
      end),
      false,
      "when_loaded: queued while which-key is not loaded"
    )
    eq(loads, 0, "when_loaded: never requires which-key")
    local fake_wk = { register = function() end } -- v2: no `add`
    package.loaded["which-key"] = fake_wk
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "which-key.nvim" })
    eq(
      got_mod,
      fake_wk,
      "when_loaded: runs with the module once it is loaded (any which-key version)"
    )
    wk = fresh()
    local ran_now
    eq(
      wk.when_loaded(function()
        ran_now = true
      end),
      true,
      "when_loaded: runs at once when which-key is already loaded"
    )
    ok(ran_now, "when_loaded: ... and did run")

    -- ----------------------------------------- a failing add() never propagates
    package.loaded["which-key"] = {
      add = function()
        error("spec format changed")
      end,
    }
    wk = fresh()
    local raised = pcall(wk.add_group, { prefix = "<leader>w", group = "W" })
    ok(raised, "add_group: a which-key that rejects the spec does not raise")

    package.loaded["which-key"] = nil
    wk = fresh()
    wk.add_group({ prefix = "<leader>w", group = "W" })
    package.loaded["which-key"] = {
      add = function()
        error("spec format changed")
      end,
    }
    local flushed_ok = pcall(wk.flush)
    ok(flushed_ok, "flush: a failing add() does not raise either")
    eq(wk.pending_count(), 0, "flush: ... and the entry is dropped, not retried forever")

    -- -------------------------------------- the keymap registry path is queued too
    package.loaded["which-key"] = nil
    wk = fresh()
    package.loaded["lib.nvim.bindings.keymap.registry"] = nil
    local registry = require("lib.nvim.bindings.keymap.registry")
    registry.register("wk_queue_probe", {
      prefix = "<leader>Q",
      which_key = { group = "queue probe" },
      actions = {
        one = { default = "<leader>Q1", mode = "n", rhs = function() end, desc = "one" },
      },
    })
    ok(
      wk.pending_count() >= 1,
      "registry.register: its group label is queued, not sent to a missing which-key"
    )
    eq(loads, 0, "registry.register: still never required which-key")
    registry.forget("wk_queue_probe")
  end)

  restore()
  if not body_ok then
    error(body_err, 0)
  end
end
