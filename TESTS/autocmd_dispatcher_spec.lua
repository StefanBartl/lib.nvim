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

  --- Run `fn` with `vim.notify` captured, and always put it back -- an assertion
  --- or an error inside `fn` must not leave the editor's notify replaced.
  ---@param fn fun(): nil
  ---@return string[]
  local function capture_notify(fn)
    local reported = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      reported[#reported + 1] = msg
    end
    local ran_ok, err = pcall(fn)
    vim.notify = orig_notify
    if not ran_ok then
      error(err, 0)
    end
    return reported
  end

  -- One throwing handler must not silence the ones after it. Plain autocmds
  -- are independent, so bundling them must not quietly give that up.
  ---@param label string
  ---@param dispatch boolean
  local function isolation_suite(label, dispatch)
    local group = ("spec.dispatcher.isolation_%s"):format(label)
    local d = dispatcher.new({
      event = "User",
      name = "spec_isolation_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })

    local ran = {}
    d.register("Boom", {
      load = function()
        error("deliberate handler failure")
      end,
      owner = "thrower",
      desc = "always throws",
      priority = 1,
      once = true,
    })
    d.register("Boom", {
      load = function()
        ran[#ran + 1] = "after"
      end,
      owner = "survivor",
      desc = "registered after the thrower",
      priority = 2,
    })
    d.attach()

    local reported = capture_notify(function()
      vim.api.nvim_exec_autocmds("User", { pattern = "Boom" })
      vim.api.nvim_exec_autocmds("User", { pattern = "Boom" })
    end)

    eq(#ran, 2, label .. ": a handler after a throwing one still runs, on every event")
    eq(#reported, 1, label .. ": a once-handler that throws is reported once, not per event")
    ok(
      reported[1]:find("deliberate handler failure", 1, true),
      label .. ": the error text is reported"
    )

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  isolation_suite("dispatch_mode", true)
  isolation_suite("bypass_mode", false)

  -- Isolation must not turn one broken handler into a notification storm: the
  -- same error is reported once, then muted until the handler runs cleanly.
  -- (Measured before the mute: 3 failing handlers x 200 events = 600 notifies.)
  ---@param label string
  ---@param dispatch boolean
  local function mute_suite(label, dispatch)
    local group = ("spec.dispatcher.mute_%s"):format(label)
    local d = dispatcher.new({
      event = "User",
      name = "spec_mute_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })

    local failing, survivor_runs = true, 0
    d.register("Mute", {
      load = function()
        if failing then
          error("flaky failure")
        end
      end,
      owner = "flaky",
      desc = "fails while `failing` is set",
      priority = 1,
    })
    d.register("Mute", {
      load = function()
        survivor_runs = survivor_runs + 1
      end,
      owner = "survivor",
      desc = "always fine",
      priority = 2,
    })
    d.attach()

    local function fire()
      vim.api.nvim_exec_autocmds("User", { pattern = "Mute" })
    end

    local first = capture_notify(function()
      for _ = 1, 5 do
        fire()
      end
    end)
    eq(#first, 1, label .. ": the same error over five events is reported once")
    eq(survivor_runs, 5, label .. ": muting the report does not skip the handler after it")

    failing = false
    eq(#capture_notify(fire), 0, label .. ": a clean run reports nothing")

    failing = true
    eq(
      #capture_notify(fire),
      1,
      label .. ": a failure after a clean run is a new episode and is reported again"
    )

    -- A re-attach is a new episode too: flipping the dispatch mode is how the
    -- dispatcher gets ruled in or out as the culprit, and an error still muted
    -- from before would look like the flip had fixed it.
    eq(#capture_notify(fire), 0, label .. ": the repeat is muted again")
    d.detach()
    d.attach()
    eq(#capture_notify(fire), 1, label .. ": a re-attach reports a still-failing handler again")

    -- error({ ... }) and error(nil) are legal; the report must not throw, and a
    -- table should come out readable rather than as an address.
    local d2 = dispatcher.new({
      event = "User",
      name = "spec_nonstring_" .. label,
      group = group .. "_nonstring",
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })
    local after = 0
    d2.register("NonString", {
      load = function()
        error({ code = 42 })
      end,
      owner = "table_error",
      desc = "throws a table",
      priority = 1,
    })
    d2.register("NonString", {
      load = function()
        error(nil)
      end,
      owner = "nil_error",
      desc = "throws nil",
      priority = 2,
    })
    d2.register("NonString", {
      load = function()
        after = after + 1
      end,
      owner = "survivor",
      desc = "always fine",
      priority = 3,
    })
    d2.attach()
    local msgs = capture_notify(function()
      vim.api.nvim_exec_autocmds("User", { pattern = "NonString" })
    end)
    eq(after, 1, label .. ": handlers after non-string errors still run")
    eq(#msgs, 2, label .. ": each non-string error is reported")
    ok(msgs[1]:find("code = 42", 1, true), label .. ": a table error is rendered readably")

    d.detach()
    d2.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
    pcall(vim.api.nvim_del_augroup_by_name, group .. "_nonstring")
  end

  mute_suite("dispatch_mode", true)
  mute_suite("bypass_mode", false)

  -- Reporting a failure must not be able to break the loop it protects, and must
  -- not cost what a muted repeat would throw away.
  ---@param label string
  ---@param dispatch boolean
  local function report_suite(label, dispatch)
    local group = ("spec.dispatcher.report_%s"):format(label)
    local d = dispatcher.new({
      event = "User",
      name = "spec_report_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })

    -- `owner` is typed string but never checked; the report must not choke on it.
    local odd_owner ---@type any
    odd_owner = true
    local after, table_errors = 0, 0
    d.register("Rep", {
      load = function()
        error("handler boom")
      end,
      owner = odd_owner,
      priority = 1,
    })
    d.register("Rep", {
      load = function()
        after = after + 1
      end,
      owner = "survivor",
      priority = 2,
    })
    d.register("Long", {
      load = function()
        error(("x"):rep(20000))
      end,
      owner = "longwinded",
    })
    d.register("Tbl", {
      load = function()
        table_errors = table_errors + 1
        error({ code = table_errors }) -- a fresh table each time
      end,
      owner = "tabler",
    })
    d.attach()

    -- A notifier that throws (a UI plugin that cannot open a window while the
    -- text is locked) must neither skip the handlers after the failing one nor
    -- lose the report: it is retried from vim.schedule.
    local delivered = {}
    local orig_notify = vim.notify
    local ran_ok, ran_err = pcall(function()
      vim.notify = function()
        error("notifier exploded")
      end
      vim.api.nvim_exec_autocmds("User", { pattern = "Rep" })
      vim.notify = function(msg)
        delivered[#delivered + 1] = msg
      end
      vim.wait(500, function()
        return #delivered > 0
      end)
    end)
    vim.notify = orig_notify
    if not ran_ok then
      error(ran_err, 0)
    end
    eq(after, 1, label .. ": a throwing notifier does not skip the handlers after the failing one")
    eq(#delivered, 1, label .. ": ...and the report is retried, not lost")
    ok(delivered[1]:find("handler boom", 1, true), label .. ": the retried report is the real one")
    ok(
      delivered[1]:find("of true", 1, true),
      label .. ": a non-string owner does not break the report"
    )

    -- One message of megabytes would stall the UI and be held as the mute key.
    local long = capture_notify(function()
      for _ = 1, 3 do
        vim.api.nvim_exec_autocmds("User", { pattern = "Long" })
      end
    end)
    eq(#long, 1, label .. ": an oversized error is still reported once, then muted")
    ok(#long[1] < 5000, label .. ": an oversized error is clipped")
    ok(long[1]:find("more bytes", 1, true), label .. ": ...and says how much was cut")

    -- Rendering a table is the expensive part of reporting it, and a muted
    -- repeat would throw the result away: every non-string error of one
    -- registration is one episode, rendered once.
    local renders = 0
    local orig_inspect = vim.inspect
    local tbl_ok, tbl_err, tbl
    tbl_ok, tbl_err = pcall(function()
      vim.inspect = function(...)
        renders = renders + 1
        return orig_inspect(...)
      end
      tbl = capture_notify(function()
        for _ = 1, 5 do
          vim.api.nvim_exec_autocmds("User", { pattern = "Tbl" })
        end
      end)
    end)
    vim.inspect = orig_inspect
    if not tbl_ok then
      error(tbl_err, 0)
    end
    eq(table_errors, 5, label .. ": the handler still ran on every event")
    eq(#tbl, 1, label .. ": five different table errors are one muted episode")
    eq(renders, 1, label .. ": a muted table error is not rendered again")
    ok(
      tbl[1]:find("code = 1", 1, true),
      label .. ": the one report is the first error, rendered readably"
    )

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  report_suite("dispatch_mode", true)
  report_suite("bypass_mode", false)

  -- `opts.pattern` is documented as the way to keep a miss in C: an event that
  -- does not match must never reach the Lua `key` function, in either mode.
  ---@param label string
  ---@param dispatch boolean
  local function pattern_suite(label, dispatch)
    local group = ("spec.dispatcher.pattern_%s"):format(label)
    local key_calls, hits = 0, 0
    local d = dispatcher.new({
      event = "User",
      name = "spec_pattern_" .. label,
      group = group,
      dispatch = dispatch,
      pattern = "PatIn",
      key = function(ev)
        key_calls = key_calls + 1
        return ev.match
      end,
    })
    d.register("PatIn", function()
      hits = hits + 1
    end)
    d.attach()

    vim.api.nvim_exec_autocmds("User", { pattern = "PatOut" })
    eq(key_calls, 0, label .. ": an event outside `pattern` never enters Lua")

    vim.api.nvim_exec_autocmds("User", { pattern = "PatIn" })
    eq(hits, 1, label .. ": an event inside `pattern` still dispatches")
    eq(key_calls, 1, label .. ": `key` still runs on a hit")

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  pattern_suite("dispatch_mode", true)
  pattern_suite("bypass_mode", false)

  -- A key's compiled form is remembered after its first use (bypass mode used to
  -- rebuild a glob's Lua pattern on every event). The memo must not change what
  -- matches: not for a glob, not for a plain key, not for one full of Lua
  -- pattern magic, however often the same keys come round again.
  ---@param label string
  ---@param dispatch boolean
  local function key_match_suite(label, dispatch)
    local group = ("spec.dispatcher.keymatch_%s"):format(label)
    local hits = { glob = 0, plain = 0, magic = 0 }
    local d = dispatcher.new({
      event = "User",
      name = "spec_keymatch_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })
    d.register("wk_*", function()
      hits.glob = hits.glob + 1
    end)
    d.register("plain.key", function()
      hits.plain = hits.plain + 1
    end)
    d.register("a-b(c)*", function()
      hits.magic = hits.magic + 1
    end)
    d.attach()

    local keys =
      { "wk_one", "wk_two", "other", "plain.key", "plainXkey", "a-b(c)tail", "aab(c)tail" }
    for _ = 1, 3 do
      for _, key in ipairs(keys) do
        vim.api.nvim_exec_autocmds("User", { pattern = key })
      end
    end
    eq(
      hits.glob,
      6,
      label .. ": a glob key keeps matching its own prefix, and only that, on repeat"
    )
    eq(hits.plain, 3, label .. ": a plain key stays exact -- `.` is not a wildcard")
    eq(hits.magic, 3, label .. ": Lua pattern magic in a glob key stays literal")

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  key_match_suite("dispatch_mode", true)
  key_match_suite("bypass_mode", false)

  -- The per-key cache is bounded. Keyed on something with an open-ended range (a
  -- file name, say) it used to grow with every distinct value ever seen.
  do
    local group = "spec.dispatcher.cache_bound"
    local hits = 0
    local d = dispatcher.new({
      event = "User",
      name = "spec_cache_bound",
      group = group,
      dispatch = true,
      key = function(ev)
        return ev.match
      end,
    })
    d.register("Churn*", function()
      hits = hits + 1
    end)
    d.attach()

    eq(d.stats().cached_keys, 0, "cache: nothing is cached before the first event")
    vim.api.nvim_exec_autocmds("User", { pattern = "ChurnA" })
    vim.api.nvim_exec_autocmds("User", { pattern = "ChurnB" })
    vim.api.nvim_exec_autocmds("User", { pattern = "ChurnA" })
    eq(d.stats().cached_keys, 2, "cache: one entry per distinct key, however often it repeats")

    d.register("Churn*", function() end)
    eq(d.stats().cached_keys, 0, "cache: a new registration drops every entry")

    hits = 0
    local distinct = 600
    for i = 1, distinct do
      vim.api.nvim_exec_autocmds("User", { pattern = "Churn" .. i })
    end
    eq(hits, distinct, "cache: every distinct key still dispatches while the cache is full")
    eq(d.stats().cached_keys, 256, "cache: capped at 256 keys, not one per key ever seen")

    -- The first of them was evicted long ago; it resolves again, and correctly.
    vim.api.nvim_exec_autocmds("User", { pattern = "Churn1" })
    eq(hits, distinct + 1, "cache: an evicted key resolves again")

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  -- A handler that changes the registry while an event is being dispatched.
  -- Native autocmds skip one deleted mid-event and leave one created mid-event
  -- for the next; dispatch mode walks a snapshot of its handler list, which
  -- used to run a just-unregistered handler once more.
  ---@param label string
  ---@param dispatch boolean
  local function inflight_suite(label, dispatch)
    local group = ("spec.dispatcher.inflight_%s"):format(label)
    local ran = {}
    local d = dispatcher.new({
      event = "User",
      name = "spec_inflight_" .. label,
      group = group,
      dispatch = dispatch,
      key = function(ev)
        return ev.match
      end,
    })
    d.register("Drop", {
      load = function()
        ran[#ran + 1] = "killer"
        d.unregister("victim")
      end,
      owner = "killer",
      priority = 1,
    })
    d.register("Drop", {
      load = function()
        ran[#ran + 1] = "victim"
      end,
      owner = "victim",
      priority = 2,
    })
    d.register("Drop", {
      load = function()
        ran[#ran + 1] = "bystander"
      end,
      owner = "bystander",
      priority = 3,
    })

    local added, late = false, 0
    d.register("Grow", {
      load = function()
        if added then
          return
        end
        added = true
        d.register("Grow", {
          load = function()
            late = late + 1
          end,
          owner = "grown",
        })
      end,
      owner = "grower",
      priority = 1,
    })
    d.attach()

    vim.api.nvim_exec_autocmds("User", { pattern = "Drop" })
    eq(
      table.concat(ran, ","),
      "killer,bystander",
      label .. ": a handler unregistered mid-event does not run in that event"
    )
    ran = {}
    vim.api.nvim_exec_autocmds("User", { pattern = "Drop" })
    eq(table.concat(ran, ","), "killer,bystander", label .. ": nor in any later one")

    vim.api.nvim_exec_autocmds("User", { pattern = "Grow" })
    eq(late, 0, label .. ": a handler registered mid-event waits for the next event")
    vim.api.nvim_exec_autocmds("User", { pattern = "Grow" })
    eq(late, 1, label .. ": and runs from then on")

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

  inflight_suite("dispatch_mode", true)
  inflight_suite("bypass_mode", false)

  -- A key that is not a string is refused at register(), at the call that passed
  -- it. Accepted, it made every event throw from inside `resolve()` -- for every
  -- key, the good handlers included -- with an error that named nobody.
  do
    local group = "spec.dispatcher.keycheck"
    local d = dispatcher.new({
      event = "User",
      name = "spec_keycheck",
      group = group,
      key = function(ev)
        return ev.match
      end,
    })
    local hits = {}
    local function hit(ctx)
      hits[ctx.key] = (hits[ctx.key] or 0) + 1
    end

    --- The error `register(keys)` raises, or nil if it accepted them.
    ---@param keys any
    ---@return string|nil
    local function refusal(keys)
      -- A closure, not `pcall(d.register, ...)`: the error's position is that of
      -- register()'s caller, and a C frame (pcall) has none to give.
      local registered, err = pcall(function()
        d.register(keys, hit)
      end)
      return (not registered) and tostring(err) or nil
    end

    ok(
      (refusal(5) or ""):find("autocmd_dispatcher_spec.lua", 1, true),
      "keycheck: the error names the caller's file, not the dispatcher's"
    )

    ok(
      (refusal(5) or ""):find("key #1 must be a string, got number", 1, true),
      "keycheck: a number is refused, and its position named"
    )
    ok(
      (refusal({ "Fine", true }) or ""):find("key #2 must be a string, got boolean", 1, true),
      "keycheck: every entry of a list is checked, not only the first"
    )
    ok(
      (refusal({ {} }) or ""):find("key #1 must be a string, got table", 1, true),
      "keycheck: a nested table is refused"
    )
    ok((refusal(nil) or ""):find("at least one key", 1, true), "keycheck: no key is still refused")
    ok(
      (refusal({}) or ""):find("at least one key", 1, true),
      "keycheck: an empty list is still refused"
    )
    eq(d.stats().total_handlers, 0, "keycheck: a refused registration leaves nothing behind")
    eq(refusal(""), nil, "keycheck: the empty string is a legal key -- a buffer with no filetype")

    d.register("Fine", hit)
    d.attach()
    local reported = capture_notify(function()
      vim.api.nvim_exec_autocmds("User", { pattern = "Fine" })
      vim.api.nvim_exec_autocmds("User", { pattern = "Other" })
    end)
    eq(#reported, 0, "keycheck: no event throws after the refusals")
    eq(hits.Fine, 1, "keycheck: the dispatcher still dispatches after them")

    -- The list is copied: editing the caller's table afterwards must neither
    -- change what the registration matches nor make it invalid.
    local keys = { "Copied" }
    d.register(keys, hit)
    keys[1] = "Changed"
    keys[2] = 42
    reported = capture_notify(function()
      vim.api.nvim_exec_autocmds("User", { pattern = "Copied" })
      vim.api.nvim_exec_autocmds("User", { pattern = "Changed" })
      vim.api.nvim_exec_autocmds("User", { pattern = "Other" })
    end)
    eq(#reported, 0, "keycheck: editing the caller's list afterwards breaks nothing")
    eq(hits.Copied, 1, "keycheck: the registration keeps the keys it was given")
    eq(hits.Changed, nil, "keycheck: ...and does not pick up the caller's later edit")

    d.detach()
    pcall(vim.api.nvim_del_augroup_by_name, group)
  end

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
