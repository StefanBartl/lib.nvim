-- TESTS/dev_deprecations_spec.lua — lib.nvim.dev.deprecations: deprecated-call
-- detection (comment/string masking, long-bracket state, suppression, version
-- gate), the root walk, the :checkhealth section and the BufWritePost watcher.

return function(H)
  local eq, ok = H.eq, H.ok
  local dep = require("lib.nvim.dev.deprecations")

  local function ids(findings)
    local out = {}
    for _, f in ipairs(findings) do
      out[#out + 1] = ("%d:%d:%s"):format(f.lnum, f.col, f.id)
    end
    return table.concat(out, " ")
  end

  -- Plain hits, column and replacement ------------------------------------
  local found = dep.scan_lines({
    "local t = vim.loop.now()",
    "vim.api.nvim_buf_set_option(0, 'ft', 'lua')",
    "vim.api.nvim_exec2('echo 1', {})",
    "vim.api.nvim_exec_lua('return 1', {})",
    "local x = vim.loopy",
  })
  eq(ids(found), "1:11:vim.loop 2:9:nvim_buf_set_option", "hits with byte columns, frontiers hold")
  eq(found[1].replacement, "vim.uv", "the replacement travels with the finding")
  eq(found[1].since, "0.10", "the deprecating version travels with the finding")
  eq(
    dep.format(found[1]),
    "1:11 vim.loop -> vim.uv (deprecated since 0.10)",
    "format() renders one finding"
  )

  eq(
    ids(dep.scan_lines({ "local a, b = vim.loop.now(), vim.loop.hrtime()" })),
    "1:14:vim.loop 1:30:vim.loop",
    "every occurrence on a line is reported"
  )

  -- `unless`: a line that already carries the replacement as a fallback.
  eq(#dep.scan_lines({ "local uv = vim.uv or vim.loop" }), 0, "a vim.uv fallback line is clean")

  -- Comments and strings are masked ----------------------------------------
  eq(#dep.scan_lines({ "-- vim.loop.now()" }), 0, "a comment line is not a call")
  eq(#dep.scan_lines({ "local n = 1 -- was vim.loop.now()" }), 0, "a trailing comment is masked")
  eq(#dep.scan_lines({ 'local s = "vim.loop.now()"' }), 0, "a double-quoted string is masked")
  eq(
    #dep.scan_lines({ "local s = 'it''s vim.loop'" }),
    0,
    "adjacent single-quoted strings are masked"
  )
  eq(
    #dep.scan_lines({ 'local s = "a \\" vim.loop"' }),
    0,
    "an escaped quote does not end the string"
  )
  eq(
    ids(dep.scan_lines({ 'local s = "x" .. tostring(vim.loop.now())' })),
    "1:27:vim.loop",
    "code after a closed string is still scanned"
  )

  -- Long strings and block comments across lines.
  eq(
    ids(dep.scan_lines({
      "local doc = [[",
      "vim.loop.now()",
      "]] local t = vim.loop.now()",
      "--[==[",
      "vim.highlight.on_yank()",
      "]==]",
      "vim.loop.now()",
    })),
    "3:14:vim.loop 7:1:vim.loop",
    "long-bracket state is carried across lines and closed again"
  )
  eq(#dep.scan_lines({ "local s = [=[ vim.loop ]=]" }), 0, "a one-line long string is masked")
  eq(
    ids(dep.scan_lines({ "local s = [[ ]=] still inside", "vim.loop ]]", "vim.loop" })),
    "3:1:vim.loop",
    "only the matching level closes a long string"
  )
  eq(dep.mask("a('x') -- c", nil), "a(   )     ", "mask() keeps the length and blanks the rest")
  local _, still_open = dep.mask("x = [==[ open", nil)
  eq(still_open, "]==]", "mask() hands the open delimiter to the next line")

  -- Suppression markers ------------------------------------------------------
  eq(
    ids(dep.scan_lines({
      "---@diagnostic disable-next-line: deprecated",
      "local a = vim.loop.now()",
      "local b = vim.loop.now() ---@diagnostic disable-line: deprecated",
      "local c = vim.loop.now()",
    })),
    "4:11:vim.loop",
    "LuaLS deprecated markers silence exactly their line"
  )

  -- Version gate and custom rules ------------------------------------------
  local future = { id = "future", pattern = "fut%(", replacement = "now()", since = "99.0" }
  local past = { id = "past", pattern = "old%(", replacement = "new()", since = "0.1" }
  eq(
    ids(dep.scan_lines({ "fut() old()" }, { rules = { future, past } })),
    "1:7:past",
    "a rule newer than the running Neovim is skipped"
  )
  local keyed = { id = "k", key = "zzz", pattern = "old%(", replacement = "new()", since = "0.1" }
  eq(#dep.scan_lines({ "old()" }, { rules = { keyed } }), 0, "an explicit key gates the pattern")
  eq(
    #dep.scan_lines({ "old() -- zzz" }, { rules = { keyed } }),
    1,
    "a line with the key runs the pattern"
  )
  eq(
    ids(dep.scan_lines({ "old() vim.loop" }, { extra_rules = { past } })),
    "1:1:past 1:7:vim.loop",
    "extra_rules extend the defaults"
  )
  eq(
    #dep.scan_lines({ "vim.loop", "vim.loop" }, { max_lines = 1 }),
    0,
    "max_lines skips a long input"
  )

  -- Buffer and root walk --------------------------------------------------
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "vim.lsp.get_active_clients()" })
  eq(ids(dep.scan_buffer(buf)), "2:1:vim.lsp.get_active_clients", "scan_buffer reads the buffer")
  eq(#dep.scan_buffer(buf, { max_lines = 1 }), 0, "max_lines skips a long buffer")
  vim.api.nvim_buf_delete(buf, { force = true })

  local root = vim.fs.normalize(vim.fn.tempname())
  local function write(rel, lines)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end
  write("init.lua", { "vim.loop.now()" })
  write("lua/cfg/a.lua", { "local ok = true", "vim.tbl_flatten({})" })
  write("lua/cfg/clean.lua", { "vim.uv.now()" })
  write(".git/hooks/x.lua", { "vim.loop.now()" })
  write(".claude/worktrees/copy/init.lua", { "vim.loop.now()" })
  write("node_modules/pkg/x.lua", { "vim.loop.now()" })
  write("lua/@types/uv.lua", { "---@meta", "vim.loop = uv" })
  write("notes.txt", { "vim.loop.now()" })

  local all, truncated = dep.scan_roots({ root })
  ok(not truncated, "a small tree is not truncated")
  eq(#all, 2, "only *.lua, outside dot-dirs/node_modules, no ---@meta file")
  eq(all[1].file, root .. "/init.lua", "findings carry their file")
  eq(all[2].file, root .. "/lua/cfg/a.lua", "files are scanned in sorted order")
  eq(all[2].lnum, 2, "file findings carry their line")
  local _, cut = dep.scan_roots({ root }, { max_files = 1 })
  ok(cut, "max_files truncates the walk and says so")
  eq(#dep.scan_roots({ root .. "/init.lua" }), 1, "a root may be a single file")
  eq(#dep.scan_file(root .. "/lua/cfg/a.lua"), 1, "scan_file reads one file")
  eq(#dep.scan_file(root .. "/lua/@types/uv.lua"), 0, "a ---@meta file is not code")
  eq(#dep.scan_file(root .. "/lua/cfg/a.lua", { max_lines = 1 }), 0, "max_lines skips a long file")

  -- :checkhealth -------------------------------------------------------------
  local calls = {}
  local fake = {
    start = function(t)
      calls[#calls + 1] = "start " .. t
    end,
    ok = function(m)
      calls[#calls + 1] = "ok " .. m
    end,
    warn = function(m)
      calls[#calls + 1] = "warn " .. m
    end,
    info = function(m)
      calls[#calls + 1] = "info " .. m
    end,
    error = function(m)
      calls[#calls + 1] = "error " .. m
    end,
  }
  H.with_patched(vim, "health", fake, function()
    eq(dep.health({ root }), 2, "health() returns the number of findings")
    eq(calls[1], "start lib.nvim: deprecated API calls", "health() opens its section")
    ok(
      calls[2]:find("^warn .*init%.lua:1:1 vim%.loop %-> vim%.uv") ~= nil,
      "each finding is a warning"
    )
    calls = {}
    dep.health({ root }, { max_listed = 1 })
    eq(calls[#calls], "info ... and 1 more", "the listing is capped")
    calls = {}
    eq(dep.health({ root .. "/lua/cfg/clean.lua" }), 0, "a clean root counts zero")
    ok(calls[2]:find("^ok no deprecated calls") ~= nil, "a clean root reports ok")

    -- `:checkhealth lib` runs the section on the user's config.
    calls = {}
    local seen
    H.with_patched(dep, "health", function(roots)
      seen = roots
      return 0
    end, function()
      require("lib.health").check()
    end)
    eq(seen and seen[1], vim.fn.stdpath("config"), ":checkhealth lib scans stdpath('config')")
  end)

  -- BufWritePost watcher -----------------------------------------------------
  local file = root .. "/watched.lua"
  vim.fn.writefile({ "local x = 1" }, file)
  vim.cmd("silent edit " .. vim.fn.fnameescape(file))
  local wbuf = vim.api.nvim_get_current_buf()
  local got
  dep.watch({
    on_findings = function(f, b)
      got = { f = f, b = b }
    end,
  })
  vim.cmd("silent write")
  eq(got, nil, "a clean save stays silent")
  vim.api.nvim_buf_set_lines(wbuf, 0, -1, false, { "local x = vim.loop.now()" })
  vim.cmd("silent write")
  ok(got ~= nil, "a save with a deprecated call reports it")
  eq(got.b, wbuf, "on_findings gets the saved buffer")
  eq(ids(got.f), "1:11:vim.loop", "on_findings gets the findings")

  -- Default reporter: one warning naming the file and the location.
  dep.watch({ max_listed = 1 })
  local msg, level
  H.with_patched(vim, "notify", function(m, l)
    msg, level = m, l
  end, function()
    vim.api.nvim_buf_set_lines(wbuf, 0, -1, false, { "vim.loop.now()", "vim.loop.now()" })
    vim.cmd("silent write")
  end)
  eq(level, vim.log.levels.WARN, "the default reporter warns")
  ok(
    msg and msg:find("watched.lua: 2 deprecated call(s)", 1, true),
    "the warning names file and count"
  )
  ok(msg and msg:find("1:1 vim.loop -> vim.uv", 1, true), "the warning lists the location")
  ok(msg and msg:find("... and 1 more", 1, true), "the listing is capped at max_listed")

  dep.unwatch()
  msg = nil
  H.with_patched(vim, "notify", function(m)
    msg = m
  end, function()
    vim.cmd("silent write")
  end)
  eq(msg, nil, "unwatch() removes the watcher")

  vim.api.nvim_buf_delete(wbuf, { force = true })
  vim.fn.delete(root, "rf")

  -- lib.nvim's own tree is clean -------------------------------------------
  -- The watcher's own repo must not carry what it warns about (bare
  -- `vim.loop`, `nvim_buf_add_highlight`, ...). Rules newer than the running
  -- Neovim are inactive, so an older CI Neovim checks a subset.
  local spec_dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
  local lua_root = vim.fs.normalize(spec_dir .. "../lua")
  local own, own_truncated = dep.scan_roots({ lua_root })
  eq(own_truncated, false, "self-scan: the whole lua/ tree was walked")
  local listed = {}
  for _, f in ipairs(own) do
    listed[#listed + 1] = (f.file or "?"):sub(#lua_root + 2) .. ":" .. dep.format(f)
  end
  eq(table.concat(listed, "\n"), "", "self-scan: no deprecated calls in lib.nvim's own lua/")
end
