-- TESTS/autocmd_dispatcher_spec.lua — lib.nvim.bindings.autocmd.dispatcher

return function(H)
  local eq, ok = H.eq, H.ok

  local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

  -- ------------------------------------------------------- register/attach
  do
    local calls = {}
    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
    })

    d.register("Alpha", function(ctx)
      calls[#calls + 1] = { key = ctx.key, from = "alpha" }
    end)

    -- Not attached yet: firing must not dispatch anything.
    vim.api.nvim_exec_autocmds("User", { pattern = "Alpha" })
    eq(#calls, 0, "no dispatch before attach()")

    d.attach()
    d.attach() -- idempotent, must not create a second autocmd

    vim.api.nvim_exec_autocmds("User", { pattern = "Alpha" })
    eq(#calls, 1, "attach() wires exactly one dispatch per real event")
    eq(calls[1].key, "Alpha", "ctx.key is the concrete matched key")

    vim.api.nvim_exec_autocmds("User", { pattern = "Unregistered" })
    eq(#calls, 1, "an unmatched key dispatches nothing")

    local stats = d.stats()
    eq(stats.total_keys, 1, "stats: one distinct key registered")
    eq(stats.total_handlers, 1, "stats: one registration")
    ok(stats.attached, "stats: attached is true after attach()")

    d.detach()
    d.detach() -- idempotent

    vim.api.nvim_exec_autocmds("User", { pattern = "Alpha" })
    eq(#calls, 1, "detach() stops dispatch")
    ok(d.stats().attached == false, "stats: attached is false after detach()")
  end

  -- ------------------------------------------------------- sort-at-registration
  do
    local order = {}
    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
    })

    -- Registered out of priority order on purpose.
    d.register("Beta", {
      load = function()
        order[#order + 1] = "prio-10"
      end,
      priority = 10,
    })
    d.register("Beta", {
      load = function()
        order[#order + 1] = "prio-negative"
      end,
      priority = -5,
    })
    d.register("Beta", function()
      order[#order + 1] = "prio-default-0-first"
    end)
    d.register("Beta", function()
      order[#order + 1] = "prio-default-0-second"
    end)

    d.attach()
    vim.api.nvim_exec_autocmds("User", { pattern = "Beta" })
    d.detach()

    eq(#order, 4, "all four matching handlers ran")
    eq(order[1], "prio-negative", "lowest priority runs first")
    eq(order[2], "prio-default-0-first", "equal priority: registration order wins (1st)")
    eq(order[3], "prio-default-0-second", "equal priority: registration order wins (2nd)")
    eq(order[4], "prio-10", "highest priority runs last")
  end

  -- --------------------------------------------------------------- glob keys
  do
    local hits = 0
    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
    })

    d.register("noice*", function()
      hits = hits + 1
    end)

    d.attach()
    vim.api.nvim_exec_autocmds("User", { pattern = "noicex" })
    vim.api.nvim_exec_autocmds("User", { pattern = "noicey_view" })
    vim.api.nvim_exec_autocmds("User", { pattern = "not-noice" })
    d.detach()

    eq(hits, 2, "glob key matches every candidate with the given prefix, nothing else")
  end

  -- ---------------------------------------------- once, per buffer, per id
  --
  -- Regression: the nvim-config prototype this module is based on keyed
  -- `once` by `tostring(handler.load)` -- a shared loader variable used by
  -- two separate register() calls collided, silently treating the second
  -- filetype's `once` as already-satisfied. Two independent register()
  -- calls that happen to close over the SAME function must still each get
  -- their own once-slot.
  do
    local shared_loader_calls = 0
    local function shared_loader()
      shared_loader_calls = shared_loader_calls + 1
    end

    -- nvim_exec_autocmds rejects combining `pattern` with `buffer` (the same
    -- either/or as autocmd creation) -- so a buffer-scoped dispatch is
    -- simulated by making it the current buffer and firing with `pattern`
    -- only; `ev.buf` then defaults to the current buffer.
    local original_buf = vim.api.nvim_get_current_buf()
    local buf_a = vim.api.nvim_create_buf(false, true)
    local buf_b = vim.api.nvim_create_buf(false, true)

    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
    })

    d.register("KeyC", { load = shared_loader, once = true })
    d.register("KeyCpp", { load = shared_loader, once = true })
    d.attach()

    vim.api.nvim_set_current_buf(buf_a)

    vim.api.nvim_exec_autocmds("User", { pattern = "KeyC" })
    eq(shared_loader_calls, 1, "first KeyC dispatch on buf_a runs the shared loader")

    vim.api.nvim_exec_autocmds("User", { pattern = "KeyC" })
    eq(shared_loader_calls, 1, "once=true: a second KeyC dispatch on the same buffer is a no-op")

    vim.api.nvim_exec_autocmds("User", { pattern = "KeyCpp" })
    eq(
      shared_loader_calls,
      2,
      "KeyCpp is an independent registration -- not satisfied by KeyC's once, despite sharing the loader"
    )

    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_exec_autocmds("User", { pattern = "KeyC" })
    eq(shared_loader_calls, 3, "once is tracked per buffer -- a different buffer runs again")

    d.detach()
    vim.api.nvim_set_current_buf(original_buf)
    vim.api.nvim_buf_delete(buf_a, { force = true })
    vim.api.nvim_buf_delete(buf_b, { force = true })
  end

  -- ------------------------------------------------------------ list of keys
  do
    local hits = {}
    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
    })

    d.register({ "KeyX", "KeyY" }, function(ctx)
      hits[#hits + 1] = ctx.key
    end)

    d.attach()
    vim.api.nvim_exec_autocmds("User", { pattern = "KeyX" })
    vim.api.nvim_exec_autocmds("User", { pattern = "KeyY" })
    d.detach()

    eq(#hits, 2, "one registration under a key list matches every listed key")
    eq(hits[1], "KeyX", "ctx.key reflects the actual matched key, not the list")
    eq(hits[2], "KeyY", "ctx.key reflects the actual matched key, not the list")
  end

  -- ------------------------------------------------------------------- context
  do
    local seen_context
    local d = dispatcher.new({
      event = "User",
      key = function(ev)
        return ev.match
      end,
      context = function()
        return "shared-context-value"
      end,
    })

    d.register("WithContext", function(ctx)
      seen_context = ctx.context
    end)

    d.attach()
    vim.api.nvim_exec_autocmds("User", { pattern = "WithContext" })
    d.detach()

    eq(seen_context, "shared-context-value", "opts.context(ev) is threaded through as ctx.context")
  end

  -- --------------------------------------------------------- dispatcher.filetype
  do
    local seen_ctx
    local ft = dispatcher.filetype.new()

    ft.register("lua", function(ctx)
      seen_ctx = ctx
    end)
    ft.attach()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_call(buf, function()
      vim.bo.filetype = "lua"
    end)

    ok(seen_ctx ~= nil, "dispatcher.filetype fires on a real FileType autocmd")
    eq(seen_ctx.key, "lua", "dispatcher.filetype keys on ev.match (the filetype)")
    ok(seen_ctx.context ~= nil, "dispatcher.filetype defaults context to a buffer.context snapshot")
    eq(seen_ctx.context.filetype, "lua", "the default context snapshot reflects the real buffer")

    ft.detach()
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ------------------------------------------------------------- unregister
  -- Without this, a shared dispatcher is unusable for anything with a
  -- setup()/teardown() cycle: a re-setup would register the same handler a
  -- second time and run it twice per event, with no way to stop it short of
  -- detach(), which takes every other owner's handlers down too. That is the
  -- exact shape of filetree.nvim's idempotent `filetree.setup()`.
  do
    local runs = { a = 0, b = 0 }
    local d = dispatcher.new({
      event = "User",
      name = "spec_unregister",
      group = "spec.dispatcher.unregister",
      key = function(ev)
        return ev.match
      end,
    })

    d.register("Go", {
      load = function()
        runs.a = runs.a + 1
      end,
      owner = "feature_a",
      desc = "A",
    })
    d.register("Go", {
      load = function()
        runs.b = runs.b + 1
      end,
      owner = "feature_b",
      desc = "B",
    })
    d.attach()

    vim.api.nvim_exec_autocmds("User", { pattern = "Go" })
    eq(runs.a, 1, "both owners ran once")
    eq(runs.b, 1, "both owners ran once")

    eq(d.unregister("feature_a"), 1, "unregister() reports how many it dropped")
    eq(d.unregister("feature_a"), 0, "unregistering an unknown owner is a no-op, not an error")

    vim.api.nvim_exec_autocmds("User", { pattern = "Go" })
    eq(runs.a, 1, "the unregistered owner no longer runs")
    eq(runs.b, 2, "the other owner is untouched")

    -- The re-setup case: unregister, register again, still exactly one run.
    d.unregister("feature_b")
    d.register("Go", {
      load = function()
        runs.b = runs.b + 1
      end,
      owner = "feature_b",
      desc = "B",
    })
    vim.api.nvim_exec_autocmds("User", { pattern = "Go" })
    eq(runs.b, 3, "re-registering after unregister runs once per event, not twice")

    eq(d.stats().total_handlers, 1, "stats() reflects the removal")

    d.detach()
    vim.api.nvim_del_augroup_by_name("spec.dispatcher.unregister")
  end

  -- `once` is tracked per registration id, so a re-registered owner must not
  -- inherit "already ran" from the cycle before it.
  do
    local runs = 0
    local d = dispatcher.new({
      event = "User",
      name = "spec_unregister_once",
      group = "spec.dispatcher.unregister_once",
      key = function(ev)
        return ev.match
      end,
    })

    local spec = {
      load = function()
        runs = runs + 1
      end,
      owner = "feat",
      once = true,
    }
    d.register("Once", spec)
    d.attach()

    vim.api.nvim_exec_autocmds("User", { pattern = "Once" })
    vim.api.nvim_exec_autocmds("User", { pattern = "Once" })
    eq(runs, 1, "once = true runs a handler at most once per buffer")

    d.unregister("feat")
    d.register("Once", spec)
    vim.api.nvim_exec_autocmds("User", { pattern = "Once" })
    eq(runs, 2, "a re-registered owner starts its per-buffer `once` clean")

    d.detach()
    vim.api.nvim_del_augroup_by_name("spec.dispatcher.unregister_once")
  end

  -- ------------------------------------------------- handlers() and registry()
  -- What the generated bindings table renders underneath a dispatcher: without
  -- it, collapsing N handlers into one autocmd would leave the page claiming a
  -- single listener where several are.
  do
    local d = dispatcher.new({
      event = { "BufEnter", "WinEnter" },
      name = "spec_registry",
      group = "spec.dispatcher.registry",
      key = function(ev)
        return ev.match
      end,
    })

    d.register("late", { load = function() end, owner = "z", desc = "runs last", priority = 10 })
    d.register({ "a", "b" }, { load = function() end, owner = "y", desc = "runs first" })

    local hs = d.handlers()
    eq(#hs, 2, "handlers() lists every registration")
    eq(hs[1].desc, "runs first", "handlers() is sorted by priority, not registration order")
    eq(#hs[1].keys, 2, "a handler registered under two keys keeps both")
    ok(hs[1].src:find("autocmd_dispatcher_spec"), "handlers() records the register() call site")

    local found
    for _, entry in ipairs(dispatcher.registry()) do
      if entry.name == "spec_registry" then
        found = entry
      end
    end
    ok(found ~= nil, "registry() lists the dispatcher by name")
    eq(found.events[1], "BufEnter", "registry() reports the dispatcher's events")
    eq(found.attached, false, "registry() reports attach state")
    eq(#found.handlers, 2, "registry() carries the handler list")
  end

  -- The dispatcher's own two autocmds are recorded and described -- they used
  -- to have no `desc` at all, and the BufWipeout cleanup had no group either.
  do
    local autocmd = require("lib.nvim.bindings.autocmd")
    local d = dispatcher.new({
      event = "User",
      name = "spec_desc",
      group = "spec.dispatcher.desc",
      key = function(ev)
        return ev.match
      end,
    })
    d.attach()

    local recs = autocmd.registered({ group = "spec.dispatcher.desc" })
    eq(#recs, 2, "attach() records the dispatch autocmd and its BufWipeout cleanup")
    for _, r in ipairs(recs) do
      ok(r.desc ~= nil and r.desc ~= "", "every autocmd the dispatcher creates has a desc")
    end

    d.detach()
    vim.api.nvim_del_augroup_by_name("spec.dispatcher.desc")
  end

  -- ------------------------------------------------------------ bypass mode
  -- `dispatch = false` builds one plain autocmd per handler instead of one for
  -- all of them: an escape hatch if a shared dispatcher misbehaves (N features
  -- hang off one object, and editing all N was the only way out), and a way to
  -- re-measure the README's cost claim in a real config rather than take it on
  -- faith.
  --
  -- A second code path nobody exercises rots, so the behaviour every caller
  -- depends on is asserted in BOTH modes below, from one suite.
  ---@param label string
  ---@param dispatch boolean
  local function shared_suite(label, dispatch)
    local group = ("spec.dispatcher.%s"):format(label)
    local calls, order = {}, {}
    local d = dispatcher.new({
      event = "User",
      name = "spec_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })

    d.register("Exact", {
      load = function(ctx)
        calls[#calls + 1] = ctx.key
        order[#order + 1] = "late"
      end,
      owner = "a",
      desc = "exact key",
      priority = 10,
    })
    d.register("Ex*", {
      load = function()
        order[#order + 1] = "early"
      end,
      owner = "b",
      desc = "glob key",
      priority = 1,
    })
    d.register({ "Multi1", "Multi2" }, {
      load = function()
        calls[#calls + 1] = "multi"
      end,
      owner = "c",
      desc = "two keys, one once-slot",
      once = true,
    })
    d.attach()

    eq(d.stats().mode, dispatch and "dispatch" or "bypass", label .. ": stats() names the mode")

    vim.api.nvim_exec_autocmds("User", { pattern = "Exact" })
    eq(#calls, 1, label .. ": an exact key fires its handler")
    eq(calls[1], "Exact", label .. ": ctx.key is the concrete key that matched")
    eq(table.concat(order, ","), "early,late", label .. ": handlers run in priority order")

    vim.api.nvim_exec_autocmds("User", { pattern = "NoMatch" })
    eq(#calls, 1, label .. ": a key with no handler fires nothing")

    -- One `once` slot across both of a registration's keys, per buffer.
    vim.api.nvim_exec_autocmds("User", { pattern = "Multi1" })
    vim.api.nvim_exec_autocmds("User", { pattern = "Multi2" })
    eq(#calls, 2, label .. ": once = true spans every key of one registration")

    -- Registering after attach() still works (it needs its own autocmd in
    -- bypass mode, where the others were built up front).
    local late = 0
    d.register("Late", {
      load = function()
        late = late + 1
      end,
      owner = "d",
      desc = "registered after attach",
    })
    vim.api.nvim_exec_autocmds("User", { pattern = "Late" })
    eq(late, 1, label .. ": a handler registered after attach() fires")

    eq(d.unregister("d"), 1, label .. ": unregister() reports what it dropped")
    vim.api.nvim_exec_autocmds("User", { pattern = "Late" })
    eq(late, 1, label .. ": an unregistered handler stops firing")

    vim.api.nvim_exec_autocmds("User", { pattern = "Exact" })
    eq(#calls, 3, label .. ": the other owners are untouched by an unregister")

    d.detach()
    eq(d.stats().attached, false, label .. ": detach() clears the attach state")
    vim.api.nvim_exec_autocmds("User", { pattern = "Exact" })
    eq(#calls, 3, label .. ": nothing fires after detach()")

    -- Found by flipping filetree between the two modes twice: sixteen records
    -- describing fourteen real autocmds, because detach() used
    -- nvim_del_autocmd directly and the registry never heard about it.
    eq(
      #require("lib.nvim.bindings.autocmd").registered({ group = group }),
      0,
      label .. ": detach() leaves no record behind"
    )

    pcall(vim.api.nvim_del_augroup_by_name, group)
    return d
  end

  shared_suite("dispatch_mode", true)
  shared_suite("bypass_mode", false)

  -- The one thing that must DIFFER: how many autocmds back the handlers.
  do
    ---@param dispatch boolean
    ---@param label string
    ---@return integer  # how many autocmds three handlers ended up behind
    local function count_autocmds(dispatch, label)
      local group = ("spec.dispatcher.count_%s"):format(label)
      local d2 = dispatcher.new({
        event = "User",
        name = "spec_count_" .. label,
        group = group,
        dispatch = dispatch,
        key = function(ev)
          return ev.match
        end,
      })
      for i = 1, 3 do
        d2.register("K" .. i, { load = function() end, owner = "o", desc = "h" .. i })
      end
      d2.attach()

      local recs = require("lib.nvim.bindings.autocmd").registered({ group = group })
      d2.detach()
      pcall(vim.api.nvim_del_augroup_by_name, group)
      return #recs
    end

    local n_dispatch = count_autocmds(true, "dispatch")
    local n_bypass = count_autocmds(false, "bypass")
    eq(n_dispatch, 2, "dispatch mode: one autocmd for all handlers, plus the BufWipeout cleanup")
    eq(n_bypass, 4, "bypass mode: one autocmd per handler, plus the BufWipeout cleanup")
  end

  -- The global switch, and the re-attach that makes it usable.
  do
    local group = "spec.dispatcher.global"
    local d = dispatcher.new({
      event = "User",
      name = "spec_global",
      group = group,
      key = function(ev)
        return ev.match
      end,
    })
    d.register("G", { load = function() end, owner = "o", desc = "g" })
    d.attach()
    eq(d.stats().mode, "dispatch", "no opt and no global: dispatch mode")

    vim.g.lib_nvim_autocmd_dispatch = false
    eq(d.stats().mode, "dispatch", "the global does not take effect until the next attach()")

    ok(dispatcher.reattach_all() >= 1, "reattach_all() re-attaches what is attached")
    eq(d.stats().mode, "bypass", "after reattach_all() the global has taken effect")

    vim.g.lib_nvim_autocmd_dispatch = nil
    dispatcher.reattach_all()
    eq(d.stats().mode, "dispatch", "clearing the global goes back to shared dispatch")

    -- An explicit opt outranks the global in both directions.
    vim.g.lib_nvim_autocmd_dispatch = false
    local forced = dispatcher.new({
      event = "User",
      name = "spec_forced",
      group = "spec.dispatcher.forced",
      dispatch = true,
      key = function(ev)
        return ev.match
      end,
    })
    forced.attach()
    eq(forced.stats().mode, "dispatch", "an explicit dispatch = true beats the global")
    forced.detach()
    vim.g.lib_nvim_autocmd_dispatch = nil

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
    pcall(vim.api.nvim_del_augroup_by_name, "spec.dispatcher.forced")
  end
end
