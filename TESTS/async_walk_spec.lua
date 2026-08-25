-- TESTS/async_walk_spec.lua — the coroutine-driven async counterparts:
-- lib.nvim.fs.collect_recursive.collect_async/files_async/dirs_async,
-- lib.nvim.fs.scan_cached.scan_async, lib.nvim.fs.scan_roots.scan_async.

return function(H)
  local eq, ok = H.eq, H.ok

  local collect = require("lib.nvim.fs.collect_recursive")
  local scan_cached = require("lib.nvim.fs.scan_cached")
  local scan_roots = require("lib.nvim.fs.scan_roots")

  ---Same elements, ignoring order (H.eq on two arrays is a reference
  ---check, not a content check — plain `~=` on tables).
  ---@param a string[]
  ---@param b string[]
  local function same_set(a, b)
    if #a ~= #b then
      return false
    end
    local sorted_a, sorted_b = vim.deepcopy(a), vim.deepcopy(b)
    table.sort(sorted_a)
    table.sort(sorted_b)
    for i = 1, #sorted_a do
      if sorted_a[i] ~= sorted_b[i] then
        return false
      end
    end
    return true
  end

  ---Run `fn(done_cb)` and block (via vim.wait) until `done_cb` was called;
  ---returns whatever was passed to `done_cb`, or nils on timeout.
  ---@param fn fun(done: fun(...))
  ---@param timeout_ms? integer
  local function await(fn, timeout_ms)
    local finished = false
    local results
    fn(function(...)
      results = { ... }
      finished = true
    end)
    ok(
      vim.wait(timeout_ms or 5000, function()
        return finished
      end, 5),
      "await: the async call finished within its timeout"
    )
    return results or {}
  end

  -- ------------------------------------------------------------- fixture

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/walk/keep", "p")
  vim.fn.mkdir(tmp .. "/walk/skipme", "p")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/a.txt")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/b.txt")
  vim.fn.writefile({ "x" }, tmp .. "/walk/skipme/c.txt")

  -- ---------------------------------------------------- collect_async parity

  local sync_all = collect.collect(tmp .. "/walk")
  local async_all = await(function(done)
    collect.collect_async(tmp .. "/walk", nil, done)
  end)[1]
  ok(same_set(async_all, sync_all), "collect_async: matches collect() exactly, same root")

  local sync_files = collect.files(tmp .. "/walk")
  local async_files = await(function(done)
    collect.files_async(tmp .. "/walk", nil, done)
  end)[1]
  eq(#async_files, #sync_files, "files_async: same count as files()")
  eq(#async_files, 3, "files_async: finds all three files")

  local sync_dirs = collect.dirs(tmp .. "/walk")
  local async_dirs = await(function(done)
    collect.dirs_async(tmp .. "/walk", nil, done)
  end)[1]
  eq(#async_dirs, #sync_dirs, "dirs_async: same count as dirs()")
  eq(#async_dirs, 2, "dirs_async: finds both directories")

  -- ------------------------------------------------------------ ignore parity

  local filtered = await(function(done)
    collect.files_async(tmp .. "/walk", {
      ignore = function(path)
        return path:match("skipme") ~= nil
      end,
    }, done)
  end)[1]
  eq(#filtered, 2, "collect_async: ignore predicate prunes the whole subtree")
  for _, p in ipairs(filtered) do
    ok(p:match("skipme") == nil, "collect_async: no surviving path is under the pruned subtree")
  end

  -- --------------------------------------------------------- missing root

  local missing = await(function(done)
    collect.collect_async(tmp .. "/does-not-exist", nil, done)
  end)[1]
  eq(#missing, 0, "collect_async: a nonexistent root settles to an empty list, not an error")

  -- ----------------------------------------------------------- cancellation

  local fired = false
  local cancel = collect.collect_async(tmp .. "/walk", nil, function()
    fired = true
  end)
  cancel()
  -- Pump the event loop for a bit without a `finished` flag to wait on —
  -- if on_done were going to fire despite cancel(), it would have by now.
  vim.wait(200, function()
    return false
  end, 10)
  ok(not fired, "collect_async: on_done never fires after cancel()")

  -- ------------------------------------------------------- scan_cached.scan_async

  local miss = await(function(done)
    scan_cached.scan_async(tmp .. "/walk", { ttl_seconds = 30 }, done)
  end)[1]
  eq(#miss, 3, "scan_cached.scan_async: uncached scan across the whole tree")

  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/d.txt")
  local hit = await(function(done)
    scan_cached.scan_async(tmp .. "/walk", { ttl_seconds = 30 }, done)
  end)[1]
  eq(#hit, 3, "scan_cached.scan_async: a cache hit returns the stale result (by design)")

  local refreshed = await(function(done)
    scan_cached.scan_async(tmp .. "/walk", { ttl_seconds = 30, refresh = true }, done)
  end)[1]
  eq(#refreshed, 4, "scan_cached.scan_async: refresh = true forces a rescan")

  -- ------------------------------------------------------- scan_roots.scan_async

  local roots_ignored = await(function(done)
    scan_roots.scan_async({ tmp .. "/walk" }, { ignore_dirs = { "skipme" } }, done)
  end)[1]
  eq(#roots_ignored, 3, "scan_roots.scan_async: honors ignore_dirs (3 files now under keep/)")

  local cache_path = tmp .. "/scan_cache.json"
  local first = await(function(done)
    scan_roots.scan_async({ tmp .. "/walk" }, { cache_path = cache_path }, done)
  end)[1]
  eq(#first, 4, "scan_roots.scan_async: uncached scan, cache written")

  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/e.txt")
  local stale = await(function(done)
    scan_roots.scan_async({ tmp .. "/walk" }, { cache_path = cache_path }, done)
  end)[1]
  eq(#stale, 4, "scan_roots.scan_async: a cache hit returns the stale result (by design)")

  local expired = await(function(done)
    scan_roots.scan_async({ tmp .. "/walk" }, { cache_path = cache_path, ttl_seconds = -1 }, done)
  end)[1]
  eq(#expired, 5, "scan_roots.scan_async: an expired TTL forces a rescan")

  -- Multiple roots, sequential chaining.
  local two_roots = await(function(done)
    scan_roots.scan_async({ tmp .. "/walk/keep", tmp .. "/walk/skipme" }, nil, done)
  end)[1]
  eq(#two_roots, 5, "scan_roots.scan_async: merges results across multiple roots")
end
