-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/nvim_helpers_spec.lua — the new lib.nvim.* adapters
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
    "lib.nvim.json",
    "lib.nvim.fs.scan_roots",
    "lib.nvim.fs.scan_cached",
    "lib.nvim.fs.watch",
    "lib.nvim.fs.path.object",
    "lib.nvim.async",
    "lib.nvim.fs.write.async",
    "lib.nvim.fs.write.batch",
    "lib.nvim.buf_win_tab.get_option",
    "lib.nvim.buf_win_tab.selection",
    "lib.nvim.buf_win_tab.word_under_cursor",
    "lib.nvim.cross",
    "lib.nvim.cross.fs.expand_path",
    "lib.nvim.cross.fs.mutate",
    "lib.nvim.cross.fs.separators.normalize",
    "lib.nvim.cross.fs.separators.unify_slashes",
    "lib.nvim.cross.uv.spawn_capture",
    "lib.nvim.cross.uv.wait_until",
    "lib.nvim.window",
    "lib.nvim.core",
    "lib.nvim.git",
    "lib.nvim.normalize",
    "lib.nvim.safe_api",
    "lib.nvim.neotree.node",
    "lib.nvim.neotree.watch",
    "lib.nvim.health",
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

  -- -------------------------------------------------------------- lib.nvim.health
  local health_mod = require("lib.nvim.health")
  local nv = vim.version()
  ok(
    health_mod.version_ok({ nv.major, nv.minor, nv.patch }),
    "health.version_ok: exactly the running version is OK"
  )
  ok(health_mod.version_ok({ 0, 0, 0 }), "health.version_ok: floor of 0.0.0 is always OK")
  ok(
    not health_mod.version_ok({ nv.major + 1, 0, 0 }),
    "health.version_ok: a future major version is not OK"
  )

  -- health.check_require just proxies to vim.health.{ok,warn,info} — assert it
  -- doesn't error for a real and a fake module at each level, since the
  -- report itself isn't capturable headlessly.
  ok(
    select(1, pcall(health_mod.check_require, "lib.nvim.health", "self", "warn")),
    "health.check_require: does not error for a module that loads"
  )
  ok(
    select(
      1,
      pcall(health_mod.check_require, "definitely_not_a_real_module_xyz", "missing", "info")
    ),
    "health.check_require: does not error for a missing module (info level)"
  )
  ok(
    select(
      1,
      pcall(health_mod.check_require, "definitely_not_a_real_module_xyz", "missing", "warn")
    ),
    "health.check_require: does not error for a missing module (warn level)"
  )

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
  ---@type Lib.Cross.Uv.SpawnCapture.Result|nil
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

  ---@type Lib.Cross.Uv.SpawnCapture.Result|nil
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

  -- unify_slashes always folds backslashes to forward slashes, regardless of OS.
  local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
  eq(unify_slashes([[C:\Users\me]]), "C:/Users/me", "unify_slashes: backslashes -> forward slashes")
  eq(unify_slashes("a/b/c"), "a/b/c", "unify_slashes: already-forward-slash paths pass through")

  -- normalize converts *to* the current OS's native separator; a single
  -- escaped backslash ("\\" in the pattern) must match one "\" per call, not two.
  local normalize_sep = require("lib.nvim.cross.fs.separators.normalize")
  local osu = uv.os_uname()
  local is_windows = (osu.version and osu.version:match("Windows"))
    or (osu.sysname and osu.sysname:match("Windows"))
  if is_windows then
    eq(normalize_sep("a/b/c"), "a\\b\\c", "normalize: forward slashes -> backslashes on Windows")
  else
    eq(
      normalize_sep([[a\b\c]]),
      "a/b/c",
      "normalize: backslashes -> forward slashes on non-Windows"
    )
  end

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
  -- The non-number handle is the case.
  ---@diagnostic disable-next-line: param-type-mismatch
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

  local sxok = safe_api.set_extmark(buf, ns, 0, 0, 5, "Comment", "hello don't world")
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

  local write_async = require("lib.nvim.fs.write.async")
  local async_p = tmp .. "/async/nested/out.txt"
  local async_ok, async_err
  write_async(async_p, "async hello\n", function(ok2, err2)
    async_ok, async_err = ok2, err2
  end)
  vim.wait(2000, function()
    return async_ok ~= nil
  end)
  ok(async_ok, "fs.write.async: succeeds and creates missing parent dirs")
  eq(async_err, nil, "fs.write.async: no error on success")
  eq(read(async_p), "async hello\n", "fs.write.async: content round-trips")

  local bad_async_ok, bad_async_err
  -- An empty `fnamemodify(path, ":h")` result (a bare filename with no
  -- directory component) is the one synchronous failure path.
  write_async("", "x", function(ok2, err2)
    bad_async_ok, bad_async_err = ok2, err2
  end)
  vim.wait(2000, function()
    return bad_async_ok ~= nil
  end)
  eq(bad_async_ok, false, "fs.write.async: invalid path -> ok = false")
  ok(bad_async_err ~= nil, "fs.write.async: invalid path yields an error message")

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

  local nvim_json = require("lib.nvim.json")
  local decoded, decode_err = nvim_json.decode('{"a":1,"list":[1,2,3]}')
  eq(decoded.a, 1, "nvim.json.decode: scalar decodes")
  eq(decoded.list[3], 3, "nvim.json.decode: nested array decodes")
  eq(decode_err, nil, "nvim.json.decode: no error on valid input")

  local bad_decoded, bad_err = nvim_json.decode("{not json")
  eq(bad_decoded, nil, "nvim.json.decode: malformed input -> nil")
  ok(bad_err ~= nil, "nvim.json.decode: malformed input yields an error message")

  local encoded, encode_err = nvim_json.encode({ a = 1 })
  eq(encoded, '{"a":1}', "nvim.json.encode: delegates to lib.lua.json.encode")
  eq(encode_err, nil, "nvim.json.encode: no error on encodable input")

  local Path = require("lib.nvim.fs.path.object")
  local path_dir = tmp .. "/path_obj"
  vim.fn.mkdir(path_dir, "p")

  local missing_p = Path.new(path_dir .. "/nope.txt")
  ok(not missing_p:exists(), "Path:exists: a missing file -> false")

  local file_p = Path.new(path_dir):joinpath("note.txt")
  eq(
    file_p.path,
    require("lib.nvim.fs.path").joinpath({ path_dir, "note.txt" }),
    "Path:joinpath: returns a new Path wrapping fs.path.joinpath's own result"
  )
  local write_ok = file_p:write("hi\n")
  ok(write_ok, "Path:write: succeeds")
  ok(file_p:exists(), "Path:exists: a written file -> true")
  ok(not file_p:is_dir(), "Path:is_dir: a file -> false")
  eq(file_p:read(), "hi\n", "Path:read: reads back what was written")

  local dir_p = Path.new(path_dir)
  ok(dir_p:exists(), "Path:exists: a real directory -> true")
  ok(dir_p:is_dir(), "Path:is_dir: a real directory -> true")

  eq(dir_p:parent().path, vim.fs.dirname(path_dir), "Path:parent: matches vim.fs.dirname")

  -- Matched by suffix, not exact string equality: collect_recursive builds
  -- its paths via raw `dir .. "/" .. name` concatenation, while
  -- Path:joinpath goes through vim.fs.joinpath's own normalization -- both
  -- correct, not necessarily byte-identical separator style.
  local names = dir_p:iter()
  local found = false
  for _, n in ipairs(names) do
    if n:match("note%.txt$") then
      found = true
      break
    end
  end
  ok(found, "Path:iter: lists the file written above")

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

  -- ERR-34: a symlinked directory that cycles back to an ancestor must not
  -- be recursed into -- following it would walk forever (in practice bounded
  -- only by an OS path-length error or a Lua stack overflow, not a real base
  -- case). Skipped on platforms/permissions where creating a symlink fails
  -- (e.g. Windows without dev mode or elevation) rather than failing the
  -- whole suite over an environment limitation unrelated to the bug.
  local cyc_root = tmp .. "/cycle"
  vim.fn.mkdir(cyc_root .. "/sub", "p")
  vim.fn.writefile({ "x" }, cyc_root .. "/sub/file.txt")
  local link_ok = uv.fs_symlink(cyc_root, cyc_root .. "/sub/loop", { dir = true })
  if link_ok then
    local cyc_result = collect.collect(cyc_root)
    eq(
      #cyc_result,
      3,
      "collect_recursive: does not recurse into a symlinked directory that cycles back to an ancestor"
    )
    local saw_loop = false
    for _, cyc_path in ipairs(cyc_result) do
      ok(
        not cyc_path:match("loop[/\\]sub"),
        "collect_recursive: never descends past the symlink into the cycle"
      )
      if cyc_path:match("loop$") then
        saw_loop = true
      end
    end
    ok(saw_loop, "collect_recursive: the symlink itself is still listed as a directory entry")
  end

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
