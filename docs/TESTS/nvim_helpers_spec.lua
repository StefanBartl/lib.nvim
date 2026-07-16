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
    "lib.nvim.debounce", "lib.nvim.debounce.buffer", "lib.nvim.dotrepeat",
    "lib.nvim.token", "lib.nvim.net.curl", "lib.nvim.cache",
    "lib.nvim.fs.collect_recursive", "lib.nvim.fs.trash", "lib.nvim.fs.read",
    "lib.nvim.fs.json", "lib.nvim.fs.scan_roots",
    "lib.nvim.fs.write.async", "lib.nvim.fs.write.batch",
    "lib.nvim.buf_win_tab.get_option", "lib.nvim.buf_win_tab.selection",
    "lib.nvim.buf_win_tab.word_under_cursor",
    "lib.nvim.cross", "lib.nvim.cross.fs.expand_path", "lib.nvim.cross.fs.mutate",
    "lib.nvim.cross.uv.spawn_capture", "lib.nvim.cross.uv.wait_until",
    "lib.nvim.window", "lib.nvim.core", "lib.nvim.git", "lib.nvim.normalize",
  }) do
    ok(require(mod) ~= nil, "loads: " .. mod)
  end

  -- -------------------------------------------------------------- lib.nvim.token
  local token = require("lib.nvim.token")
  eq(#token.gen_token(16), 16, "token.gen_token: honors the requested length")
  ok(token.gen_token(16) ~= token.gen_token(16), "token.gen_token: consecutive tokens differ")

  -- --------------------------------------------------------------- lib.nvim.core
  local core = require("lib.nvim.core")
  ok(core.has_exec("nvim"), "core.has_exec: finds nvim on PATH")
  ok(not core.has_exec("definitely_not_a_real_binary_xyz"), "core.has_exec: rejects a missing binary")
  eq(core.first_available({ "definitely_not_a_real_binary_xyz", "nvim" }), "nvim",
    "core.first_available: skips missing candidates")
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
    "is_usable_window", "target_window", "ensure_bottom", "make_focusable",
    "force_focus", "focus_and_bottom", "open_named_scratch",
  }) do
    eq(type(window[fn]), "function", "window aggregator exports " .. fn)
  end
  eq(type(window.make_scratch), "function", "window aggregator: pre-existing make_scratch still wired")
  ok(window.is_usable_window(vim.api.nvim_get_current_win()), "window.is_usable_window: a normal window")
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
  ok(mutate.rename_file(tmp .. "/mut/copy.txt", tmp .. "/mut/moved.txt"), "cross.fs.mutate.rename_file")
  ok(uv.fs_stat(tmp .. "/mut/moved.txt") ~= nil, "cross.fs.mutate: the renamed file exists")
  ok(mutate.delete_file(tmp .. "/mut/moved.txt"), "cross.fs.mutate.delete_file")
  eq(uv.fs_stat(tmp .. "/mut/moved.txt"), nil, "cross.fs.mutate: the file is gone")
  ok(not mutate.delete_file(tmp .. "/mut/ghost.txt"), "cross.fs.mutate: deleting a missing file fails cleanly")

  local scan_roots = require("lib.nvim.fs.scan_roots")
  eq(#scan_roots.scan({ tmp .. "/walk" }, { ignore_dirs = { "skipme" } }), 1,
    "scan_roots: honors ignore_dirs")

  local cache_p = tmp .. "/scan_cache.json"
  eq(#scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p }), 2, "scan_roots: uncached scan")
  vim.fn.writefile({ "x" }, tmp .. "/walk/keep/c.txt")
  eq(#scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p }), 2,
    "scan_roots: a cache hit returns the stale result (by design)")
  eq(#scan_roots.scan({ tmp .. "/walk" }, { cache_path = cache_p, ttl_seconds = -1 }), 3,
    "scan_roots: an expired TTL forces a rescan")
end
