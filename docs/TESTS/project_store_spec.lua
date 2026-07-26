-- docs/TESTS/project_store_spec.lua — lib.nvim.store.project

return function(H)
  local eq, ok = H.eq, H.ok

  local store = require("lib.nvim.store.project")

  local storage_dir = vim.fn.tempname()
  vim.fn.mkdir(storage_dir, "p")

  local project_a = vim.fn.tempname()
  vim.fn.mkdir(project_a, "p")
  local project_b = vim.fn.tempname()
  vim.fn.mkdir(project_b, "p")

  local opts_a = { dir = storage_dir, path = project_a }
  local opts_b = { dir = storage_dir, path = project_b }

  eq(store.load("settings", opts_a), nil, "store.project: load on missing key is nil")

  local root_a = store.root(opts_a)
  ok(type(root_a) == "string" and #root_a > 0, "store.project: root() resolves a non-empty string")
  eq(store.root(opts_a), root_a, "store.project: root() is stable across calls for the same path")

  local saved, err = store.save("settings", { theme = "dark" }, opts_a)
  eq(saved, true, "store.project: save reports success: " .. tostring(err))

  local loaded = store.load("settings", opts_a)
  eq(loaded.theme, "dark", "store.project: load roundtrips the saved data")

  -- A different project's root must not see project A's data — same key,
  -- different `path`, must resolve to a different on-disk subdirectory.
  eq(store.load("settings", opts_b), nil, "store.project: storage is isolated per project root")

  store.save("settings", { theme = "light" }, opts_b)
  eq(
    store.load("settings", opts_a).theme,
    "dark",
    "store.project: project A unaffected by project B's save"
  )
  eq(store.load("settings", opts_b).theme, "light", "store.project: project B keeps its own value")

  local st = store.stats("settings", opts_a)
  eq(st.exists, true, "store.project: stats.exists after save")
  ok(st.size_bytes > 0, "store.project: stats.size_bytes is positive")

  eq(store.clear("settings", opts_a), true, "store.project: clear reports success")
  eq(store.load("settings", opts_a), nil, "store.project: load after clear is nil")
  eq(store.load("settings", opts_b).theme, "light", "store.project: clearing A leaves B untouched")

  -- TTL expiry, mirroring cache.disk's own spec: rewrite with an old
  -- `saved_at` rather than sleeping for real.
  store.save("settings", { theme = "dark" }, opts_a)
  local root_key = store.root(opts_a)
  local hash = (function()
    -- Recompute the same short_hash the module uses internally, purely to
    -- locate the on-disk file for this whitebox TTL check.
    local h = 5381
    for i = 1, #root_key do
      h = (h * 33 + root_key:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
  end)()
  local path = storage_dir .. "/" .. hash .. "/settings.json"
  local f = assert(io.open(path, "r"), "store.project spec: settings.json must exist")
  local entry = vim.json.decode(f:read("*a"))
  f:close()
  entry.saved_at = os.time() - 1000000
  local fw = assert(io.open(path, "w"), "store.project spec: settings.json must be writable")
  fw:write(vim.json.encode(entry))
  fw:close()

  eq(
    store.load("settings", vim.tbl_extend("force", opts_a, { ttl_seconds = 60 })),
    nil,
    "store.project: expired entry (by ttl_seconds) loads as nil"
  )
  ok(store.load("settings", opts_a) ~= nil, "store.project: load without ttl_seconds ignores age")
end
