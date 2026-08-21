-- docs/TESTS/autocmd_dispatcher_spec.lua — lib.nvim.autocmd.dispatcher

return function(H)
  local eq, ok = H.eq, H.ok

  local dispatcher = require("lib.nvim.autocmd.dispatcher")

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
end
