-- docs/TESTS/nvim_helpers_spec.lua — the new lib.nvim.* adapters
--
-- Covers what is testable headlessly: module loading, aggregator wiring, and
-- real filesystem round-trips. Anything needing a UI, a network peer, or a
-- real desktop trash bin (net.curl, fs.trash, debounce timing, dotrepeat) is
-- load-checked only — driving those needs an interactive session.

return function(H)
  local eq, ok = H.eq, H.ok
  local uv = vim.uv or vim.loop

  -- Every new module must at least load cleanly.
  for _, mod in ipairs({
    "lib.nvim.debounce",
    "lib.nvim.debounce.buffer",
    "lib.nvim.dotrepeat",
    "lib.nvim.token",
    "lib.nvim.net.curl",
    "lib.nvim.cache",
    "lib.nvim.fs.collect_recursive",
    "lib.nvim.fs.trash",
    "lib.nvim.fs.read",
    "lib.nvim.fs.json",
    "lib.nvim.fs.scan_roots",
    "lib.nvim.fs.scan_cached",
    "lib.nvim.fs.write.async",
    "lib.nvim.fs.write.batch",
    "lib.nvim.buf_win_tab.get_option",
    "lib.nvim.buf_win_tab.selection",
    "lib.nvim.buf_win_tab.word_under_cursor",
    "lib.nvim.cross",
    "lib.nvim.cross.fs.expand_path",
    "lib.nvim.cross.fs.mutate",
    "lib.nvim.cross.uv.spawn_capture",
    "lib.nvim.cross.uv.wait_until",
    "lib.nvim.window",
    "lib.nvim.core",
    "lib.nvim.git",
    "lib.nvim.normalize",
    "lib.nvim.safe_api",
    "lib.nvim.neotree.node",
    "lib.nvim.neotree.watch",
  }) do
    ok(require(mod) ~= nil, "loads: " .. mod)
  end

  -- ------------------------------------------------------- lib.nvim.neotree.watch
  local watch = require("lib.nvim.neotree.watch")
  -- Without neo-tree's fs_watch present, install() is a graceful no-op and the
  -- registry stays empty, so release()/count() are safe to call unconditionally.
  eq(watch.install(), false, "watch.install: false when neo-tree fs_watch absent")
  eq(watch.installed(), false, "watch.installed: false when not installed")
  eq(watch.count(), 0, "watch.count: empty registry")
  eq(#watch.list(), 0, "watch.list: empty when nothing tracked")
  eq(watch.release("Z:/nope"), 0, "watch.release: no-op on empty registry")
  eq(watch.release({ "a", "b" }), 0, "watch.release: accepts a path list")
  eq(
    watch.with_release("x", function()
      return 7
    end),
    7,
    "watch.with_release: runs fn and returns its value"
  )

  -- -------------------------------------------------------------- lib.nvim.token
  local token = require("lib.nvim.token")
  eq(#token.gen_token(16), 16, "token.gen_token: honors the requested length")
  ok(token.gen_token(16) ~= token.gen_token(16), "token.gen_token: consecutive tokens differ")

  -- --------------------------------------------------------------- lib.nvim.core
  local core = require("lib.nvim.core")
  ok(core.has_exec("nvim"), "core.has_exec: finds nvim on PATH")
  ok(
    not core.has_exec("definitely_not_a_real_binary_xyz"),
    "core.has_exec: rejects a missing binary"
  )
  eq(
    core.first_available({ "definitely_not_a_real_binary_xyz", "nvim" }),
    "nvim",
    "core.first_available: skips missing candidates"
  )
  eq(core.first_available({ "nope_xyz_abc" }), nil, "core.first_available: none available -> nil")

  -- ---------------------------------------------------------- lib.nvim.normalize
  local norm = require("lib.nvim.normalize")
  ok(norm.is_one_of("b", { "a", "b" }), "normalize.is_one_of: match")
  ok(not norm.is_one_of("z", { "a", "b" }), "normalize.is_one_of: no match")
  ok(norm.buf_valid(vim.api.nvim_get_current_buf()), "normalize.buf_valid: current buffer")
  ok(not norm.buf_valid(99999), "normalize.buf_valid: bogus handle")
  ok(not norm.buf_valid("nope"), "normalize.buf_valid: non-number")
  ok(norm.win_valid(vim.api.nvim_get_current_win()), "normalize.win_valid: current window")
  ok(not norm.win_valid(99999), "normalize.win_valid: bogus handle")

  -- -------------------------------------------------------------- lib.nvim.cross
  local cross = require("lib.nvim.cross")
  eq(type(cross.fs.expand_path), "function", "cross aggregator: fs.expand_path wired")
  eq(type(cross.fs.mutate.mkdir_p), "function", "cross aggregator: fs.mutate wired")
  eq(type(cross.uv.spawn_capture), "function", "cross aggregator: uv.spawn_capture wired")

  -- Actually invoke it (not just load-check): this is what caught spawn_capture
  -- passing argv through table.unpack, which LuaJIT does not provide.
  local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")
  local spawn_result = nil
  spawn_capture({ vim.v.progpath, "--version" }, {}, function(r)
    spawn_result = r
  end)
  vim.wait(5000, function()
    return spawn_result ~= nil
  end)
  ok(spawn_result ~= nil, "spawn_capture: callback fires")
  ok(spawn_result.ok, "spawn_capture: nvim --version exits 0")
  ok(spawn_result.stdout:match("NVIM") ~= nil, "spawn_capture: captures stdout")

  local bad_spawn_result = nil
  spawn_capture({ "definitely_not_a_real_binary_xyz" }, {}, function(r)
    bad_spawn_result = r
  end)
  vim.wait(2000, function()
    return bad_spawn_result ~= nil
  end)
  ok(bad_spawn_result ~= nil, "spawn_capture: callback fires for a missing binary")
  ok(not bad_spawn_result.ok, "spawn_capture: missing binary -> not ok")
  eq(type(cross.uv.wait_until), "function", "cross aggregator: uv.wait_until wired")
  eq(type(cross.run.run_detached), "function", "cross aggregator: run.run_detached wired")
  eq(type(cross.fs.cwd), "function", "cross aggregator: pre-existing fs.cwd still wired")

  local expand_path = require("lib.nvim.cross.fs.expand_path")
  vim.env.LIBNVIM_SPEC_VAR = "xyz"
  eq(expand_path("$LIBNVIM_SPEC_VAR/a"), "xyz/a", "expand_path: $VAR")
  eq(expand_path("${LIBNVIM_SPEC_VAR}/a"), "xyz/a", "expand_path: ${VAR}")
  eq(expand_path("%LIBNVIM_SPEC_VAR%/a"), "xyz/a", "expand_path: %VAR%")
  eq(expand_path("$NOT_SET_VAR_ABC"), "$NOT_SET_VAR_ABC", "expand_path: unset var left verbatim")
  ok(expand_path("~/x"):match("^~") == nil, "expand_path: tilde expands to a home dir")

  -- ------------------------------------------------------------- lib.nvim.window
  local window = require("lib.nvim.window")
  for _, fn in ipairs({
    "is_usable_window",
    "target_window",
    "ensure_bottom",
    "make_focusable",
    "force_focus",
    "focus_and_bottom",
    "open_named_scratch",
  }) do
    eq(type(window[fn]), "function", "window aggregator exports " .. fn)
  end
  eq(
    type(window.make_scratch),
    "function",
    "window aggregator: pre-existing make_scratch still wired"
  )
  ok(
    window.is_usable_window(vim.api.nvim_get_current_win()),
    "window.is_usable_window: a normal window"
  )
  ok(not window.is_usable_window(99999), "window.is_usable_window: bogus handle")

  -- ---------------------------------------------------------------- lib.nvim.git
  local git = require("lib.nvim.git")
  eq(type(git.status_porcelain), "function", "git.status_porcelain: exported")
  local st = git.status_porcelain()
  ok(st == nil or type(st) == "table", "git.status_porcelain: returns a table or nil")

  -- --------------------------------------------- buf_win_tab.word_under_cursor
  local word_under_cursor = require("lib.nvim.buf_win_tab.word_under_cursor")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello don't world" })
  vim.api.nvim_win_set_buf(0, buf)

  vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- on "hello"
  eq(word_under_cursor().word, "hello", "word_under_cursor: plain word")

  vim.api.nvim_win_set_cursor(0, { 1, 7 }) -- inside "don't"
  eq(word_under_cursor().word, "don't", "word_under_cursor: default pattern keeps apostrophes")

  vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- the space between words
  eq(word_under_cursor(), nil, "word_under_cursor: cursor on a non-word char -> nil")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local w = word_under_cursor()
  eq(w.start_col, 0, "word_under_cursor: start_col is 0-based")
  eq(w.end_col, 5, "word_under_cursor: end_col is 0-based exclusive")
  eq(w.row, 1, "word_under_cursor: row is 1-based")

  -- ------------------------------------------------ buf_win_tab.get_option
  local get_option = require("lib.nvim.buf_win_tab.get_option")
  vim.bo[buf].filetype = "lua"
  eq(get_option(buf, "filetype"), "lua", "get_option: reads filetype")
  eq(get_option(99999, "filetype"), nil, "get_option: invalid buffer -> nil")

  -- ------------------------------------------------------------ safe_api
  local safe_api = require("lib.nvim.safe_api")

  ok(safe_api.is_valid_buffer(buf), "safe_api.is_valid_buffer: real buffer")
  ok(not safe_api.is_valid_buffer(99999), "safe_api.is_valid_buffer: bogus handle")
  ok(not safe_api.is_valid_buffer("nope"), "safe_api.is_valid_buffer: non-number")

  local win = vim.api.nvim_get_current_win()
  ok(safe_api.is_valid_window(win), "safe_api.is_valid_window: real window")
  ok(not safe_api.is_valid_window(99999), "safe_api.is_valid_window: bogus handle")

  local sok, slines = safe_api.buf_get_lines(buf, 0, -1, false)
  ok(sok, "safe_api.buf_get_lines: succeeds on a valid buffer")
  eq(slines[1], "hello don't world", "safe_api.buf_get_lines: reads the content")

  local bok, _, berr = safe_api.buf_get_lines(99999, 0, -1, false)
  ok(not bok, "safe_api.buf_get_lines: fails on an invalid buffer")
  ok(berr ~= nil, "safe_api.buf_get_lines: yields an error message")

  local cok, cnt = safe_api.buf_line_count(buf)
  ok(cok, "safe_api.buf_line_count: succeeds")
  eq(cnt, 1, "safe_api.buf_line_count: counts lines")

  local ns = vim.api.nvim_create_namespace("safe_api_spec")
  local eok, eid = safe_api.buf_set_extmark(buf, ns, 0, 0, {})
  ok(eok, "safe_api.buf_set_extmark: succeeds")
  ok(type(eid) == "number", "safe_api.buf_set_extmark: returns an id")

  local sxok, _, sxerr = safe_api.set_extmark(buf, ns, 0, 0, 5, "Comment", "hello don't world")
  ok(sxok, "safe_api.set_extmark: in-range columns succeed")
  local oxok, _, oxerr = safe_api.set_extmark(buf, ns, 0, 0, 999, "Comment", "hello don't world")
  ok(not oxok, "safe_api.set_extmark: out-of-range col_end fails cleanly")
  ok(oxerr:match("out of range") ~= nil, "safe_api.set_extmark: error mentions the range")

  local wok, wval = safe_api.win_get_option(win, "wrap")
  ok(wok, "safe_api.win_get_option: succeeds")
  eq(type(wval), "boolean", "safe_api.win_get_option: returns the option value")

  local rcalls = 0
  local rok, rres = safe_api.with_retry(function()
    rcalls = rcalls + 1
    if rcalls < 2 then
      error("invalid handle")
    end
    return "ok"
  end, 3)
  ok(rok, "safe_api.with_retry: succeeds after a transient handle-like failure")
  eq(rres, "ok", "safe_api.with_retry: returns the eventual result")
  eq(rcalls, 2, "safe_api.with_retry: retried exactly once")

  local nrok, _, nrerr = safe_api.with_retry(function()
    error("totally unrelated failure")
  end, 3)
  ok(not nrok, "safe_api.with_retry: does not retry a non-handle error")
  ok(nrerr:match("unrelated") ~= nil, "safe_api.with_retry: surfaces the original error")

  -- ---------------------------------------------------- fs round-trips on disk
  local tmp = vim.fn.tempname()

  local write_to_file = require("lib.nvim.fs.write.to_file")
  local read = require("lib.nvim.fs.read")
  local p = tmp .. "/sub/dir/file.txt"
  ok(write_to_file(p, "hello"), "fs.write.to_file: creates parent dirs and writes")
  ok(read(p):match("hello") ~= nil, "fs.read: reads the content back")
  local missing, rerr = read(tmp .. "/nope.txt")
  eq(missing, nil, "fs.read: missing file -> nil")
  ok(rerr ~= nil, "fs.read: missing file yields an error message")

  -- Regression: io.open's text mode ("w"/"r") silently rewrites "\n" <->
  -- "\r\n" on Windows. Both must be binary-mode so writes/reads are
  -- byte-exact and platform-independent.
  local crlf_check_p = tmp .. "/crlf_check.txt"
  ok(write_to_file(crlf_check_p, "a\nb\n"), "fs.write.to_file: writes multi-line content")
  local raw_f = io.open(crlf_check_p, "rb")
  local raw = raw_f:read("*a")
  raw_f:close()
  eq(raw, "a\nb\n", "fs.write.to_file: no CRLF translation on write (binary mode)")
  eq(read(crlf_check_p), "a\nb\n", "fs.read: no CRLF collapsing on read (binary mode)")

  local write_append = require("lib.nvim.fs.write.append")
  local append_p = tmp .. "/append_check.txt"
  ok(write_append(append_p, "x\n"), "fs.write.append: first append")
  ok(write_append(append_p, "y\n"), "fs.write.append: second append")
  local append_f = io.open(append_p, "rb")
  local append_raw = append_f:read("*a")
  append_f:close()
  eq(append_raw, "x\ny\n", "fs.write.append: no CRLF translation (binary mode)")

  local json = require("lib.nvim.fs.json")
  local jp = tmp .. "/data.json"
  ok(json.write(jp, { a = 1, b = { "x", "y" } }), "fs.json.write: succeeds")
  local jdata = json.read(jp)
  eq(jdata.a, 1, "fs.json: scalar round-trips")
  eq(jdata.b[2], "y", "fs.json: nested array round-trips")
  eq(uv.fs_stat(jp .. ".tmp"), nil, "fs.json.write: the atomic .tmp file is cleaned up")
  local jbad, jerr = json.read(tmp .. "/nope.json")
  eq(jbad, nil, "fs.json.read: missing file -> nil")
  ok(jerr ~= nil, "fs.json.read: missing file yields an error message")

  local collect = require("lib.nvim.fs.collect_recursive")
  vim.fn.mkdir(tmp .. "/walk/keep", "p")
  vim.fn.mkdir(tmp .. "/walk/skipme", "p")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/a.txt")
  vim.fn.writefile({ "x" }, tmp .. "/walk/skipme/b.txt")
  eq(#collect.files(tmp .. "/walk"), 2, "collect_recursive.files: walks recursively")
  eq(#collect.dirs(tmp .. "/walk"), 2, "collect_recursive.dirs: finds directories")
  local filtered = collect.files(tmp .. "/walk", {
    ignore = function(path)
      return path:match("skipme") ~= nil
    end,
  })
  eq(#filtered, 1, "collect_recursive: ignore predicate prunes the whole subtree")
  ok(filtered[1]:match("a%.txt") ~= nil, "collect_recursive: the surviving file is the right one")

  local mutate = require("lib.nvim.cross.fs.mutate")
  ok(mutate.mkdir_p(tmp .. "/mut"), "cross.fs.mutate.mkdir_p")
  vim.fn.writefile({ "data" }, tmp .. "/mut/src.txt")
  ok(mutate.copy_file(tmp .. "/mut/src.txt", tmp .. "/mut/copy.txt"), "cross.fs.mutate.copy_file")
  ok(uv.fs_stat(tmp .. "/mut/copy.txt") ~= nil, "cross.fs.mutate: the copy exists")
  ok(
    mutate.rename_file(tmp .. "/mut/copy.txt", tmp .. "/mut/moved.txt"),
    "cross.fs.mutate.rename_file"
  )
  ok(uv.fs_stat(tmp .. "/mut/moved.txt") ~= nil, "cross.fs.mutate: the renamed file exists")
  ok(mutate.delete_file(tmp .. "/mut/moved.txt"), "cross.fs.mutate.delete_file")
  eq(uv.fs_stat(tmp .. "/mut/moved.txt"), nil, "cross.fs.mutate: the file is gone")
  ok(
    not mutate.delete_file(tmp .. "/mut/ghost.txt"),
    "cross.fs.mutate: deleting a missing file fails cleanly"
  )

  -- Retry layer. Driven through mutate.retry with a fake op rather than a real
  -- locked file: a genuine EPERM needs a second process holding a handle, which
  -- is not reproducible in a headless spec (and not at all off Windows).
  local prev_attempts = mutate.defaults.attempts
  mutate.defaults.attempts = 3

  local tries = 0
  local r_ok = mutate.retry(function()
    tries = tries + 1
    if tries < 3 then
      return false, "EPERM: operation not permitted"
    end
    return true, nil
  end)
  ok(r_ok, "mutate.retry: a transient EPERM is retried until it succeeds")
  eq(tries, 3, "mutate.retry: it took exactly the expected number of attempts")

  tries = 0
  local n_ok, n_err = mutate.retry(function()
    tries = tries + 1
    return false, "ENOENT: no such file or directory"
  end)
  ok(not n_ok, "mutate.retry: a non-transient error fails")
  eq(tries, 1, "mutate.retry: a non-transient error is not retried")
  ok(n_err:match("ENOENT") ~= nil, "mutate.retry: the original error is returned")

  tries = 0
  local e_ok, e_err = mutate.retry(function()
    tries = tries + 1
    return false, "EBUSY: resource busy or locked"
  end)
  ok(not e_ok, "mutate.retry: exhausting all attempts fails")
  eq(tries, 3, "mutate.retry: it stops after `attempts` tries")
  ok(e_err:match("EBUSY") ~= nil, "mutate.retry: the last attempt's error is returned")

  local hooks = 0
  mutate.retry(function()
    return false, "EACCES: permission denied"
  end, {
    on_retry = function()
      hooks = hooks + 1
    end,
  })
  eq(hooks, 2, "mutate.retry: on_retry fires between attempts, not after the last")

  mutate.defaults.attempts = prev_attempts

  local scan_roots = require("lib.nvim.fs.scan_roots")
  eq(
    #scan_roots.scan({ tmp .. "/walk" }, { ignore_dirs = { "skipme" } }),
    1,
    "scan_roots: honors ignore_dirs"
  )

  local cache_p = tmp .. "/scan_cache.json"
  eq(#scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p }), 2, "scan_roots: uncached scan")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/c.txt")
  eq(
    #scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p }),
    2,
    "scan_roots: a cache hit returns the stale result (by design)"
  )
  eq(
    #scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p, ttl_seconds = -1 }),
    3,
    "scan_roots: an expired TTL forces a rescan"
  )

  local scan_cached = require("lib.nvim.fs.scan_cached")
  eq(#scan_cached.scan(tmp .. "/walk"), 3, "scan_cached: uncached scan across the whole tree")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/d.txt")
  eq(
    #scan_cached.scan(tmp .. "/walk"),
    3,
    "scan_cached: a cache hit returns the stale result (by design)"
  )
  eq(
    #scan_cached.scan(tmp .. "/walk", { refresh = true }),
    4,
    "scan_cached: refresh=true forces a rescan"
  )
  eq(
    #scan_cached.scan(tmp .. "/walk", { ttl_seconds = 0, refresh = true }),
    4,
    "scan_cached: refresh with ttl_seconds=0 seeds a zero-ttl entry"
  )
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/e.txt")
  eq(
    #scan_cached.scan(tmp .. "/walk", { ttl_seconds = 0 }),
    5,
    "scan_cached: a zero-second ttl entry reads as expired on the next call"
  )
end
