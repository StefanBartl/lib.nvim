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

  local missing_results = await(function(done)
    collect.collect_async(tmp .. "/does-not-exist", nil, done)
  end)
  local missing, missing_errors = missing_results[1], missing_results[2]
  eq(#missing, 0, "collect_async: a nonexistent root settles to an empty list, not a raise")
  ok(
    type(missing_errors) == "table" and #missing_errors == 1,
    "collect_async: but reports the unreadable root, unlike a genuinely empty tree"
  )
  local clean_errors = await(function(done)
    collect.collect_async(tmp .. "/walk/keep", nil, done)
  end)[2]
  eq(clean_errors, nil, "collect_async: a readable tree reports no errors")

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

  -- Bounded concurrency over the roots: never more than `concurrency` walks in flight, and the answer keeps
  -- the order of `roots` whichever walk finishes first.
  local many = {}
  for i = 1, 6 do
    local dir = ("%s/walk_many/r%d"):format(tmp, i)
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "x" }, dir .. "/f.txt")
    many[#many + 1] = dir
  end
  local real_collect_async = collect.collect_async
  ---@param opts table|nil
  ---@param delay_first? integer ms to hold back the first root's answer (so it finishes last)
  local function max_in_flight(opts, delay_first)
    local current, peak, result = 0, 0, nil
    H.with_patched(collect, "collect_async", function(root, o, on_done)
      current = current + 1
      peak = math.max(peak, current)
      return real_collect_async(root, o, function(...)
        current = current - 1
        if delay_first and root == many[1] then
          local args = { ... }
          vim.defer_fn(function()
            on_done(unpack(args))
          end, delay_first)
        else
          on_done(...)
        end
      end)
    end, function()
      result = await(function(done)
        scan_roots.scan_async(many, opts, done)
      end)[1]
    end)
    return peak, result
  end
  local peak1, seq = max_in_flight(nil)
  local peak3, par = max_in_flight({ concurrency = 3 })
  eq(peak1, 1, "scan_roots.scan_async: one root at a time by default")
  eq(peak3, 3, "scan_roots.scan_async: concurrency = 3 keeps three walks in flight, no more")
  eq(#par, 6, "scan_roots.scan_async: concurrency: every root is scanned")
  ok(
    vim.deep_equal(par, seq),
    "scan_roots.scan_async: concurrency: the result keeps the order of roots"
  )

  -- the first root answers last, the merged result still starts with its file
  local _, late = max_in_flight({ concurrency = 3 }, 80)
  ok(
    vim.deep_equal(late, seq),
    "scan_roots.scan_async: order of roots kept although the first root finishes last"
  )

  -- the stub is gone after the helper, even though it patched a module function
  eq(
    collect.collect_async,
    real_collect_async,
    "scan_roots.scan_async: the test restores collect_async"
  )

  -- a failing root is reported, the others are merged in order, nothing is cached
  for _, c in ipairs({ 1, 3 }) do
    local cache = tmp .. ("/scan_err_%d.json"):format(c)
    local bad_root = tmp .. "/walk_many/does_not_exist"
    local out = await(function(done)
      scan_roots.scan_async(
        { many[1], bad_root, many[2] },
        { concurrency = c, cache_path = cache },
        done
      )
    end)
    eq(#out[1], 2, ("scan_roots.scan_async (concurrency %d): the good roots are merged"):format(c))
    ok(
      out[1][1]:find("r1", 1, true) and out[1][2]:find("r2", 1, true),
      ("scan_roots.scan_async (concurrency %d): in the order of roots"):format(c)
    )
    eq(
      out[2] and #out[2],
      1,
      ("scan_roots.scan_async (concurrency %d): one error for the bad root"):format(c)
    )
    eq(
      (vim.uv or vim.loop).fs_stat(cache),
      nil,
      ("scan_roots.scan_async (concurrency %d): a scan with errors is not cached"):format(c)
    )
  end

  -- a walk that throws is an error for that root only; on_done fires exactly once
  do
    local calls = 0
    local out
    H.with_patched(collect, "collect_async", function(root, o, on_done)
      if root == many[2] then
        error("walk exploded", 0)
      end
      return real_collect_async(root, o, on_done)
    end, function()
      out = await(function(done)
        scan_roots.scan_async({ many[1], many[2], many[3] }, { concurrency = 2 }, function(...)
          calls = calls + 1
          done(...)
        end)
      end)
    end)
    vim.wait(100)
    eq(calls, 1, "scan_roots.scan_async: on_done fires exactly once after a throwing walk")
    eq(#out[1], 2, "scan_roots.scan_async: the other roots are still merged after a throwing walk")
    ok(
      out[2] and #out[2] == 1 and out[2][1]:find("walk exploded", 1, true) ~= nil,
      "scan_roots.scan_async: the throwing root is reported with its message"
    )
  end

  -- no roots: one scheduled answer, an empty list and no errors
  do
    local sync_called, answer = false, nil
    local is_sync = true
    scan_roots.scan_async({}, nil, function(...)
      answer = { ... }
      sync_called = is_sync
    end)
    is_sync = false
    vim.wait(500, function()
      return answer ~= nil
    end)
    ok(
      answer ~= nil and #answer[1] == 0 and answer[2] == nil,
      "scan_roots.scan_async: no roots -> {} and no errors"
    )
    eq(
      sync_called,
      false,
      "scan_roots.scan_async: no roots -> on_done is scheduled, not synchronous"
    )
  end

  -- odd concurrency values are clamped, never stall: every root is scanned
  for _, c in ipairs({ 0, -1, "2", 2.5 }) do
    local res = await(function(done)
      scan_roots.scan_async(many, { concurrency = c }, done)
    end, 5000)
    ok(
      res and res[1] and #res[1] == 6,
      "scan_roots.scan_async: concurrency " .. vim.inspect(c) .. " still scans every root"
    )
  end
end
