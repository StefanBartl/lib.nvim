-- docs/TESTS/cache_spec.lua — lib.nvim.cache.disk, lib.nvim.cache.memory

return function(H)
  local eq, ok = H.eq, H.ok

  -- -------------------------------------------------------------- cache.disk
  local disk = require("lib.nvim.cache.disk")

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local opts = { dir = dir }

  eq(disk.load("missing", opts), nil, "cache.disk: load on missing namespace is nil")
  eq(disk.stats("missing", opts).exists, false, "cache.disk: stats on missing namespace")

  local saved, err = disk.save("widgets", { { id = 1 }, { id = 2 } }, opts)
  eq(saved, true, "cache.disk: save reports success: " .. tostring(err))

  local loaded = disk.load("widgets", opts)
  eq(#loaded, 2, "cache.disk: load roundtrips the saved data")
  eq(loaded[1].id, 1, "cache.disk: nested data survives the roundtrip")

  local st = disk.stats("widgets", opts)
  eq(st.exists, true, "cache.disk: stats.exists after save")
  ok(st.size_bytes > 0, "cache.disk: stats.size_bytes is positive")
  ok(st.age_seconds ~= nil and st.age_seconds >= 0, "cache.disk: stats.age_seconds present")

  -- TTL expiry: rewrite the file with an old `saved_at` to avoid a real sleep.
  local path = dir .. "/widgets.json"
  local f = assert(io.open(path, "r"), "cache.disk spec: widgets.json must exist")
  local entry = vim.json.decode(f:read("*a"))
  f:close()
  entry.saved_at = os.time() - 1000000
  local fw = assert(io.open(path, "w"), "cache.disk spec: widgets.json must be writable")
  fw:write(vim.json.encode(entry))
  fw:close()

  eq(disk.load("widgets", vim.tbl_extend("force", opts, { ttl_seconds = 60 })), nil,
    "cache.disk: expired entry (by ttl_seconds) loads as nil")
  ok(disk.load("widgets", opts) ~= nil, "cache.disk: load without ttl_seconds ignores age")

  eq(disk.clear("widgets", opts), true, "cache.disk: clear reports success")
  eq(disk.load("widgets", opts), nil, "cache.disk: load after clear is nil")
  eq(disk.clear("widgets", opts), true, "cache.disk: clear on an already-absent namespace is still ok")

  -- ------------------------------------------------------------ cache.memory
  local memory = require("lib.nvim.cache.memory")

  local ns = memory.namespace("spec.widgets", { ttl = 0.02 })
  eq(ns.get("a"), nil, "cache.memory: get on empty namespace is nil")

  ns.set("a", 42)
  eq(ns.get("a"), 42, "cache.memory: set/get roundtrip")

  local s1 = ns.stats()
  eq(s1.hits, 1, "cache.memory: stats.hits after one hit")
  eq(s1.misses, 1, "cache.memory: stats.misses after one miss")

  vim.wait(40) -- outlast the 0.02s TTL
  eq(ns.get("a"), nil, "cache.memory: entry expires after its TTL")
  ok(ns.stats().evictions >= 1, "cache.memory: expiry counts as an eviction")

  -- changedtick-bound entries
  local bufnr = vim.api.nvim_create_buf(false, true)
  local ns2 = memory.namespace("spec.tickbound")
  ns2.set("k", "v1", bufnr)
  eq(ns2.get("k", bufnr), "v1", "cache.memory: tick-bound get before any edit")

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "changed" })
  eq(ns2.get("k", bufnr), nil, "cache.memory: tick-bound entry evicted after the buffer changes")

  ns2.set("k2", "v2")
  ns2.invalidate("k2")
  eq(ns2.get("k2"), nil, "cache.memory: invalidate drops a single key")

  ns2.set("k3", "v3")
  ns2.clear()
  eq(ns2.get("k3"), nil, "cache.memory: clear drops every key in the namespace")

  local all = memory.get_all_stats()
  ok(#all >= 2, "cache.memory: get_all_stats reports every namespace")
  memory.print_all_stats() -- smoke: must not error

  -- auto-invalidation is opt-in and toggleable
  eq(memory.is_auto_invalidation_enabled(), false, "cache.memory: auto-invalidation off by default")

  memory.setup_auto_invalidation({ prefix = "lib.nvim.cache.memory.spec" })
  eq(memory.is_auto_invalidation_enabled(), true, "cache.memory: setup_auto_invalidation enables it")

  -- Idempotent: calling setup again must not duplicate the autocmds. Note
  -- nvim_create_autocmd({"TextChanged", "TextChangedI"}, ...) registers one
  -- entry per event, so the group holds 3 entries (2 + BufWritePost) for a
  -- single `setup_auto_invalidation` call — stable across repeats, not 6.
  memory.setup_auto_invalidation({ prefix = "lib.nvim.cache.memory.spec" })
  local autocmds = vim.api.nvim_get_autocmds({ group = "lib.nvim.cache.memory.spec" })
  eq(#autocmds, 3, "cache.memory: re-running setup does not duplicate autocmds")

  local ns3 = memory.namespace("spec.auto")
  ns3.set("x", "y", bufnr)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  eq(ns3.get("x", bufnr), nil, "cache.memory: BufWritePost clears namespaces while enabled")

  memory.disable_auto_invalidation()
  eq(memory.is_auto_invalidation_enabled(), false, "cache.memory: disable_auto_invalidation turns it off")

  ns3.set("x2", "y2", bufnr)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  eq(ns3.get("x2", bufnr), "y2", "cache.memory: BufWritePost is a no-op once disabled")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end
