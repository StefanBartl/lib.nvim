-- TESTS/contract_doc_spec.lua -- lib.nvim.contract.doc: head, seal, encode and error document of a machine contract.

---@diagnostic disable: duplicate-set-field
-- Why: the spec replaces vim.system for the git lookup and the seams of an instance on purpose.

return function(H)
  local ok = H.ok
  local doc = require("lib.nvim.contract.doc")
  local json = require("lib.nvim.json.canonical")

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local function has(text, part, msg)
    ok(type(text) == "string" and text:find(part, 1, true), msg or ("expected " .. part))
  end

  ---An instance with fixed time and engine, like a golden-file run.
  local function fixed(cfg)
    local d = doc.new(vim.tbl_extend("force", { plugin = "tasks.nvim", schema = 1 }, cfg or {}))
    d.clock = function()
      return "2026-01-01T00:00:00Z"
    end
    d.engine_info = function()
      return { version = "0.1.0", git = "abc1234", nvim = "v0.11.0" }
    end
    return d
  end

  -- ── new: the config is checked, with the position of the caller ──
  local function refused(cfg, part)
    -- through a function of this file and not `pcall(doc.new, cfg)`: a message has a position only when something
    -- of Lua is the caller (and no tail call, which would hide it), and the position must be the caller's
    local good, err = pcall(function()
      doc.new(cfg)
    end)
    ok(not good, "expected an error for " .. vim.inspect(cfg))
    has(tostring(err), part)
    has(tostring(err), "contract_doc_spec.lua:", "the position is the caller's: " .. tostring(err))
  end
  refused(nil, "needs a table")
  refused({ schema = 1 }, "plugin")
  refused({ plugin = "", schema = 1 }, "plugin")
  refused({ plugin = "x.nvim" }, "schema")
  refused({ plugin = "x.nvim", schema = 0 }, "schema")
  refused({ plugin = "x.nvim", schema = 1.5 }, "schema")
  refused({ plugin = "x.nvim", schema = "1" }, "schema")
  refused({ plugin = "x.nvim", schema = math.huge }, "schema") -- every document would fail to encode
  refused({ plugin = "x.nvim", schema = 0 / 0 }, "schema")
  -- every other key is checked too: a wrong one used to fail later inside the library, or corrupt the head
  for _, bad in ipairs({ "big", 0, -1, 1.5, 0 / 0, true }) do
    refused({ plugin = "x.nvim", schema = 1, max_bytes = bad }, "max_bytes")
  end
  for _, key in ipairs({ "kind_prefix", "scope_key", "placeholder", "plugin_root" }) do
    for _, bad in ipairs({ 5, true, "" }) do
      refused({ plugin = "x.nvim", schema = 1, [key] = bad }, key)
    end
  end
  for _, key in ipairs({ "engine_version", "too_large_hint" }) do
    for _, bad in ipairs({ 5, true }) do
      refused({ plugin = "x.nvim", schema = 1, [key] = bad }, key)
    end
  end
  -- a scope_key of a field the documents have would overwrite it ('engine' made the engine vanish from every head)
  for _, field in ipairs({
    "schema",
    "plugin",
    "kind",
    "generated_at",
    "engine",
    "rev",
    "digest",
    "code",
    "message",
    "retryable",
    "details",
  }) do
    refused({ plugin = "x.nvim", schema = 1, scope_key = field }, "scope_key")
  end
  has(
    select(2, pcall(doc.new, { plugin = "x.nvim", schema = 1, scope_key = "engine" })),
    "'engine'",
    "the message names the field"
  )
  local _, blamed = pcall(function()
    local made = doc.new({ plugin = "x.nvim", schema = 1, scope_key = "engine" }) -- no tail call: it would hide the caller
    return made
  end)
  has(blamed, "contract_doc_spec.lua", "the position is the caller's, not the library's")
  ok(
    pcall(doc.new, {
      plugin = "x.nvim",
      schema = 1,
      kind_prefix = "xx",
      scope_key = "source",
      placeholder = "<s>",
      engine_version = "",
      too_large_hint = "less",
      plugin_root = "/opt/x",
      max_bytes = 1,
    }),
    "a right config is still accepted"
  )
  ok(
    pcall(doc.new, { plugin = "x.nvim", schema = 1, max_bytes = math.huge }),
    "no limit at all is a limit nobody reaches"
  )

  -- ── defaults and names ──
  local plain = doc.new({ plugin = "tasks.nvim", schema = 1 })
  eq(plain.SCHEMA, 1)
  eq(plain.PLUGIN, "tasks.nvim")
  eq(plain.ENGINE_VERSION, "0.0.0")
  eq(plain.MAX_DOC_BYTES, 8 * 1024 * 1024)
  eq(plain.ERROR_KIND, "tasks.error", "the prefix is the plugin without .nvim")
  eq(plain.PLACEHOLDER, "<vault>")
  eq(plain.kind("hello"), "tasks.hello")
  local custom = doc.new({
    plugin = "rules.nvim",
    schema = 2,
    kind_prefix = "rl",
    scope_key = "source",
    engine_version = "9.9",
    max_bytes = 100,
  })
  eq(custom.ERROR_KIND, "rl.error")
  eq(custom.PLACEHOLDER, "<source>")
  eq(custom.ENGINE_VERSION, "9.9")
  eq(custom.MAX_DOC_BYTES, 100)
  ok(plain.head ~= custom.head, "every instance has its own functions")

  -- ── head ──
  local d = fixed()
  eq(d.head("tasks.hello", "C:/Users/me/tasks-vault"), {
    schema = 1,
    plugin = "tasks.nvim",
    kind = "tasks.hello",
    generated_at = "2026-01-01T00:00:00Z",
    vault = json.object({ id = "tasks-vault" }),
    engine = json.object({ version = "0.1.0", git = "abc1234", nvim = "v0.11.0" }),
  })
  eq(d.head("tasks.hello").vault.id, "", "no root: an empty id")
  eq(
    json.encode(d.head("tasks.hello")),
    '{"engine":{"git":"abc1234","nvim":"v0.11.0","version":"0.1.0"},"generated_at":"2026-01-01T00:00:00Z","kind":"tasks.hello","plugin":"tasks.nvim","schema":1,"vault":{"id":""}}',
    "the bytes of a head are fixed (a golden file depends on them)"
  )
  local rh =
    fixed({ scope_key = "source", plugin = "rules.nvim" }).head("rules.hello", "/a/b/wkdbook-Lua")
  eq(rh.source.id, "wkdbook-Lua", "the scope field has the plugin's name")
  eq(rh.vault, nil, "and no other")
  eq(rh.plugin, "rules.nvim")
  -- the root may be spelled any way: the source has the same name and the same bytes (a trailing slash gave "")
  for _, root in ipairs({
    "/a/b/vault",
    "/a/b/vault/",
    "/a/b/vault//",
    "C:/a/b/vault/",
    "C:\\a\\b\\vault",
    "C:\\a\\b\\vault\\",
    "C:\\a/b\\vault/",
  }) do
    eq(d.head("k", root).vault.id, "vault", root)
    eq(
      d.seal(d.head("k", root)).digest,
      d.seal(d.head("k", "/a/b/vault")).digest,
      "same source, same digest: " .. root
    )
  end
  for _, root in ipairs({ "", "/", "//", "C:/", "C:\\", "C:" }) do
    eq(d.head("k", root).vault.id, "", "a root without a name has no name: " .. root)
  end

  -- ── the seams are read when the document is made ──
  local seam = doc.new({ plugin = "tasks.nvim", schema = 1 })
  seam.clock = function()
    return "T1"
  end
  eq(seam.head("k").generated_at, "T1")
  seam.clock = function()
    return "T2"
  end
  eq(seam.head("k").generated_at, "T2", "replaced later, used at once")
  local real = doc.new({ plugin = "tasks.nvim", schema = 1 })
  ok(
    real.clock():match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"),
    "the real clock is UTC ISO 8601: " .. real.clock()
  )
  -- the shape alone is no proof of UTC (a local time with a literal Z has it too). Bracketed by two readings of UTC
  -- (immune to a second that rolls over): a clock of local time fails here on every host that is not on UTC ...
  local utc_before = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local stamp = real.clock()
  local utc_after = os.date("!%Y-%m-%dT%H:%M:%SZ")
  ok(
    utc_before <= stamp and stamp <= utc_after,
    ("the clock is UTC: %s is not between %s and %s"):format(stamp, utc_before, utc_after)
  )
  -- ... and on a host that is on UTC the format asked for decides: "!" is Lua's way to say UTC
  local asked_format
  local real_date = os.date
  H.with_patched(os, "date", function(format, ...)
    asked_format = format
    return real_date(format, ...)
  end, function()
    real.clock()
  end)
  eq(type(asked_format) == "string" and asked_format:sub(1, 1), "!", "the clock asks for UTC")
  local info = real.engine_info()
  eq(info.version, "0.0.0")
  eq(info.git, "unknown", "without plugin_root git is never asked")
  ok(info.nvim:match("^v?%d+%.%d+"), "the nvim version: " .. info.nvim)
  eq(
    info.nvim,
    tostring(vim.version()),
    "it is what vim.version() prints (no leading v, build metadata)"
  )

  -- vim.version() asks Neovim over its API (0.7 ms, 99% of a small document) and cannot change: once per instance
  do
    local real_version, asked = vim.version, 0
    vim.version = function()
      asked = asked + 1
      return "0.99.1+stub"
    end
    local run_ok, err = pcall(function()
      local once = doc.new({ plugin = "tasks.nvim", schema = 1 })
      local first = once.engine_info()
      once.engine_info()
      eq(once.head("k", "/r").engine.nvim, "0.99.1+stub", "the head says the same")
      eq(first.nvim, "0.99.1+stub")
      eq(asked, 1, "asked once for three looks")
      first.nvim = "changed by a caller"
      eq(once.engine_info().nvim, "0.99.1+stub", "every look is a table of its own")
      doc.new({ plugin = "tasks.nvim", schema = 1 }).engine_info()
      eq(asked, 2, "another instance asks for itself (nothing is shared between instances)")
    end)
    vim.version = real_version
    assert(run_ok, err)
  end

  -- ── engine_info: the commit of the plugin checkout ──
  local is_win_or_mac = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1
  ---What git prints for `rev-parse --show-toplevel --short HEAD`: the top level (the folder of `-C`, unless the step
  ---names another as `top`) and then the step's text.
  ---@param argv string[]
  ---@param step table
  ---@return string
  local function top_and(argv, step)
    return step[3] and ((step.top or argv[3]) .. "\n" .. step[3]) or ""
  end
  ---Run `fn(git, calls)` with an instance whose plugin_root is set and a scripted `vim.system`.
  ---@param script (table|string)[]  per call: `{ code, signal, stdout }`, or a string = the start fails with it
  ---@param fn function
  ---@param plugin_root? string
  local function with_script(script, fn, plugin_root)
    local real_system = vim.system
    local calls, argvs = {}, {}
    vim.system = function(argv)
      argvs[#argvs + 1] = argv
      local step = script[#calls + 1]
      return {
        wait = function(_, ms)
          calls[#calls + 1] = ms
          if type(step) == "string" then
            error(step)
          end
          return { code = step[1], signal = step[2], stdout = top_and(argv, step) }
        end,
      }
    end
    local instance = doc.new({
      plugin = "tasks.nvim",
      schema = 1,
      plugin_root = plugin_root or "/opt/plugins/tasks.nvim/",
    })
    local run_ok, err = pcall(fn, function()
      return instance.engine_info().git
    end, calls, argvs)
    vim.system = real_system
    assert(run_ok, err)
  end

  with_script({ { 124, 9 }, { 0, 0, "abc1234\n" } }, function(git, calls, argvs)
    eq(git(), "unknown", "no answer in time")
    eq(git(), "abc1234", "the next call asks again; the newline is cut")
    eq(git(), "abc1234", "an answer is kept")
    eq(#calls, 2, "no third look")
    eq(
      argvs[1],
      { "git", "-C", "/opt/plugins/tasks.nvim", "rev-parse", "--show-toplevel", "--short", "HEAD" },
      "the checkout, slash-cleaned"
    )
  end)
  with_script({ { 124, 9 }, { 124, 9 }, { 124, 9 } }, function(git, calls)
    git()
    git()
    git()
    eq(calls, { 2000, 500, 500 }, "2 s for the first look, 0.5 s for each retry")
  end)
  with_script({ { 128, 0 } }, function(git, calls)
    eq(git(), "unknown", "git said there is no commit")
    eq(git(), "unknown")
    eq(#calls, 1, "an answer of git is not asked again")
  end)
  with_script({ "spawn failed", { 0, 0, "def5678\n" } }, function(git, calls)
    eq(git(), "unknown", "the start failed")
    eq(git(), "def5678", "recovers on a later call")
    eq(#calls, 2)
  end)
  with_script({ { 124, 9 }, { 124, 9 }, { 124, 9 }, { 0, 0, "aaa1111\n" } }, function(git, calls)
    for _ = 1, 5 do
      eq(git(), "unknown")
    end
    eq(#calls, 3, "the limit of three looks")
  end)
  with_script({ { 124, 0 }, { 0, 0, "bbb2222\n" } }, function(git, calls)
    eq(git(), "unknown")
    eq(git(), "bbb2222", "code 124 without a signal is not pinned either")
    eq(#calls, 2)
  end)
  -- a git that was killed from outside (the signal is set, the code is no 124: 0, or 128 + the signal) has given no
  -- answer: it is asked again, and not pinned as "unknown" for the life of the process
  with_script({ { 0, 9 }, { 137, 9 }, { 0, 0, "eee5555\n" } }, function(git, calls)
    eq(git(), "unknown", "killed by a signal, code 0")
    eq(git(), "unknown", "killed by a signal, code 137")
    eq(git(), "eee5555", "and the third look gets the answer")
    eq(#calls, 3, "neither of the first two was an answer to keep")
  end)
  with_script({ { 1, 15 }, { 0, 0, "fff6666\n" } }, function(git, calls)
    eq(git(), "unknown", "terminated, code 1")
    eq(git(), "fff6666", "asked again")
    eq(#calls, 2)
  end)
  with_script({ { 0, 0, "fatal: not a hash\n" }, { 0, 0, "ccc3333\n" } }, function(git, calls)
    eq(git(), "unknown")
    eq(git(), "unknown")
    eq(#calls, 1, "an answer of git that is not a commit is an answer: kept")
  end)
  -- a root is trimmed of its trailing slashes, but a root keeps its own: `-C ""` and `-C C:` mean the current directory
  for _, case in ipairs({
    { "/", "/" },
    { "//", "//" },
    { "C:/", "C:/" },
    { "C:\\", "C:/" },
    { "/opt/p/", "/opt/p" },
    { "/opt/p//", "/opt/p" },
    { "C:\\opt\\p\\", "C:/opt/p" },
    { "//server/share/", "//server/share" },
  }) do
    with_script({ { 0, 0, "abc1234\n" } }, function(git, _, argvs)
      eq(git(), "abc1234")
      eq(
        argvs[1],
        { "git", "-C", case[2], "rev-parse", "--show-toplevel", "--short", "HEAD" },
        "plugin_root " .. case[1]
      )
    end, case[1])
  end
  -- without plugin_root git is never started
  do
    local started = 0
    local git
    H.with_patched(vim, "system", function()
      started = started + 1
      error("must not start git")
    end, function()
      local no_root = doc.new({ plugin = "tasks.nvim", schema = 1 })
      git = no_root.engine_info().git
      no_root.engine_info()
    end)
    eq(git, "unknown")
    eq(started, 0, "no checkout named: no process")
  end

  -- a plugin_root that is no checkout of its own: `-C` walks up, git names the top level of the repo above it,
  -- and the commit of that repo is not the plugin's
  with_script({ { 0, 0, "abc1234", top = "/opt/plugins" } }, function(git, calls)
    eq(git(), "unknown", "the top level is another folder")
    eq(git(), "unknown")
    eq(#calls, 1, "that is an answer: kept")
  end)
  -- the same folder in another spelling is the same top level (git prints forward slashes, Windows has any case)
  with_script({ { 0, 0, "abc1234", top = "C:/Opt/P" } }, function(git)
    eq(
      git(),
      is_win_or_mac and "abc1234" or "unknown",
      "case decides only where the disk ignores it"
    )
  end, "C:\\opt\\p\\")

  -- the real git: the checkout of this repo, a folder inside it, and an inherited GIT_DIR that would win over -C
  local repo = vim.fs.normalize(vim.fn.getcwd())
  local probe = vim
    .system({ "git", "-C", repo, "rev-parse", "--show-toplevel", "--short", "HEAD" }, { text = true })
    :wait(10000)
  local top_line, sha_line = (probe.stdout or ""):match("^([^\r\n]*)\r?\n(%x+)")
  if probe.code == 0 and top_line and vim.fs.normalize(top_line):lower() == repo:lower() then
    local function real_git(root)
      return doc.new({ plugin = "tasks.nvim", schema = 1, plugin_root = root }).engine_info().git
    end
    eq(real_git(repo), sha_line, "the checkout itself: its commit")
    eq(
      real_git(repo .. "/lua"),
      "unknown",
      "a folder inside the checkout is no checkout of its own"
    )
    local saved = { vim.env.GIT_DIR, vim.env.GIT_WORK_TREE }
    vim.env.GIT_DIR = repo .. "/no-such-git-dir"
    vim.env.GIT_WORK_TREE = repo .. "/lua"
    local ran, inherited = pcall(real_git, repo)
    vim.env.GIT_DIR, vim.env.GIT_WORK_TREE = saved[1], saved[2]
    eq(
      { ran, inherited },
      { true, sha_line },
      "an inherited GIT_DIR / GIT_WORK_TREE does not reach git"
    )
  else
    H.skipped("contract_doc: real git", "the suite does not run from a git checkout of lib.nvim")
  end

  -- ── prewarm: the lookup in the background, the callback fired later by the spec ──
  ---Run `fn(inst, async, waits)` with a stubbed `vim.system`: a call with a callback is recorded in `async`
  ---(`{ argv, opts, cb }`, fired by the spec), a synchronous `:wait(ms)` answers from `sync_script` and records `ms`.
  ---@param sync_script table[]
  ---@param fn function
  ---@param cfg? table
  local function with_async(sync_script, fn, cfg)
    local async, waits = {}, {}
    H.with_patched(vim, "system", function(argv, opts, cb)
      if cb then
        async[#async + 1] = { argv = argv, opts = opts, cb = cb }
        return {}
      end
      return {
        wait = function(_, ms)
          waits[#waits + 1] = ms
          local step = sync_script[#waits]
          return { code = step[1], signal = step[2], stdout = top_and(argv, step) }
        end,
      }
    end, function()
      local inst = doc.new(vim.tbl_extend("force", {
        plugin = "tasks.nvim",
        schema = 1,
        plugin_root = "/opt/plugins/tasks.nvim",
      }, cfg or {}))
      fn(inst, async, waits)
    end)
  end

  with_async({}, function(inst, async, waits)
    inst.prewarm()
    eq(#async, 1, "one background lookup")
    eq(
      async[1].argv,
      { "git", "-C", "/opt/plugins/tasks.nvim", "rev-parse", "--show-toplevel", "--short", "HEAD" }
    )
    eq(async[1].opts.timeout, 2000, "the first look gets 2 s")
    eq(
      { async[1].opts.text, async[1].opts.clear_env },
      { true, true },
      "text, in an environment of its own"
    )
    inst.prewarm()
    eq(#async, 1, "a second prewarm while it runs starts nothing")
    eq(inst.head("k", "/r").engine.git, "unknown", "while it runs: no wait")
    eq(inst.engine_info().git, "unknown")
    eq(#waits, 0, "nothing synchronous while the lookup runs")
    async[1].cb({ code = 0, signal = 0, stdout = "/opt/plugins/tasks.nvim\nabc1234\n" })
    eq(inst.engine_info().git, "abc1234", "the callback fills the cache: unknown was not pinned")
    inst.prewarm()
    eq(#async, 1, "a known answer: prewarm does nothing")
    eq(#waits, 0)
  end)
  -- `new{ prewarm = true }` starts it right away
  with_async({}, function(inst, async)
    eq(#async, 1, "started by new")
    async[1].cb({ code = 0, signal = 0, stdout = "/opt/plugins/tasks.nvim\nbcd2345\n" })
    eq(inst.engine_info().git, "bcd2345")
  end, { prewarm = true })
  -- a timeout of the background lookup is one of the three tries; the retry is synchronous and quick
  with_async({ { 124, 9 }, { 124, 9 }, { 0, 0, "never" } }, function(inst, async, waits)
    inst.prewarm()
    async[1].cb({ code = 124, signal = 9, stdout = "" })
    eq(inst.engine_info().git, "unknown", "first retry")
    eq(inst.engine_info().git, "unknown", "second retry: the third look")
    eq(inst.engine_info().git, "unknown")
    eq(waits, { 500, 500 }, "two retries of 0.5 s after the background look, then no more")
  end)
  -- a definite answer of git in the background stays (no retry)
  with_async({}, function(inst, async, waits)
    inst.prewarm()
    async[1].cb({ code = 128, signal = 0, stdout = "" })
    eq(inst.engine_info().git, "unknown")
    inst.prewarm()
    eq(#async, 1, "nothing asked again")
    eq(#waits, 0)
  end)
  -- a prewarm after a timed-out look gets the retry wait
  with_async({ { 124, 9 } }, function(inst, async)
    eq(inst.engine_info().git, "unknown")
    inst.prewarm()
    eq(async[1].opts.timeout, 500)
  end)
  -- the start fails: one try, nothing hangs
  do
    local inst
    H.with_patched(vim, "system", function()
      error("spawn failed")
    end, function()
      inst = doc.new({ plugin = "tasks.nvim", schema = 1, plugin_root = "/opt/p" })
      inst.prewarm()
    end)
    with_script({ { 0, 0, "eee5555\n" } }, function(_, calls)
      eq(inst.engine_info().git, "eee5555", "a later look recovers")
      eq(calls, { 500 }, "the failed start was one try: the retry wait")
    end)
  end
  -- without plugin_root prewarm starts nothing
  do
    local started = 0
    H.with_patched(vim, "system", function()
      started = started + 1
    end, function()
      local no_root = doc.new({ plugin = "tasks.nvim", schema = 1, prewarm = true })
      no_root.prewarm()
      eq(no_root.engine_info().git, "unknown")
    end)
    eq(started, 0)
  end
  ok(
    not pcall(doc.new, { plugin = "tasks.nvim", schema = 1, prewarm = "yes" }),
    "prewarm must be a boolean"
  )
  -- two instances do not share what they know
  with_script({ { 0, 0, "ddd4444\n" } }, function(git)
    eq(git(), "ddd4444")
    local other = doc.new({ plugin = "x.nvim", schema = 1 })
    eq(other.engine_info().git, "unknown", "another instance, another cache")
  end)

  -- ── seal: rev and digest ──
  local sealed = d.seal(d.head("tasks.snapshot", "/v"), "rev:abc123")
  eq(sealed.rev, "rev:abc123")
  ok(
    sealed.digest:match("^sha256:%x+$") and #sealed.digest == 7 + 16,
    "digest: sha256: and 16 digits"
  )
  eq(sealed.generated_at, "2026-01-01T00:00:00Z", "the time is back after the sealing")
  eq(sealed.engine.git, "abc1234", "and the engine")
  local nil_rev = d.seal(d.head("tasks.done_preview", "/v"), nil)
  eq(nil_rev.rev, nil, "no rev: the field is absent")
  ok(nil_rev.digest ~= nil, "but the digest is there")
  -- the digest says what the source contains: not when, not by which build
  local first = d.seal(d.head("k", "/v"), "r")
  d.clock = function()
    return "2030-12-31T23:59:59Z"
  end
  d.engine_info = function()
    return { version = "9.9", git = "ffffff0", nvim = "v0.12.0" }
  end
  local later = d.seal(d.head("k", "/v"), "r")
  eq(later.digest, first.digest, "same content, same digest, whenever and by whichever build")
  later.items = { 1 }
  local changed = d.seal(later, "r")
  ok(changed.digest ~= first.digest, "the digest follows the content")
  eq(
    d.seal({ kind = "k", a = 1 }, "r").digest,
    d.seal({ a = 1, kind = "k" }, "r").digest,
    "key order is no content"
  )
  ok(
    d.seal({ kind = "k", a = 1 }, "r").digest ~= d.seal({ kind = "k", a = 1 }, "s").digest,
    "rev is content"
  )

  -- a value JSON cannot hold: seal raises (as `encode` words it), and the document is as it was, not stripped
  do
    local sd = fixed()
    local function sick(value)
      local s = sd.head("tasks.snapshot", "/v")
      s.rules = { { score = value } }
      return s
    end
    for what, value in pairs({ nan = 0 / 0, inf = math.huge, ["a function"] = function() end }) do
      local s = sick(value)
      local sealed_ok, seal_err = pcall(sd.seal, s, "r")
      eq(sealed_ok, false, what)
      has(tostring(seal_err), "$.rules[1].score", what .. ": the message names the path")
      ok(not tostring(seal_err):find("%.lua:%d+:"), what .. ": and has no file:line")
      eq(s.generated_at, "2026-01-01T00:00:00Z", what .. ": the time is still there")
      eq(s.engine.git, "abc1234", what .. ": and the engine")
      eq(s.digest, nil, what .. ": and there is no digest")
      eq(s.rev, nil, what .. ": and no rev that was never sealed")
      eq(select(2, sd.encode(s)).code, "internal", what .. ": encode alone returns the error")
    end
    -- a document sealed before keeps what it had when the second seal fails
    local again = sd.seal(sd.head("k", "/v"), "r1")
    local first_digest = again.digest
    again.rules = { { score = 0 / 0 } }
    ok(not pcall(sd.seal, again, "r2"))
    eq({ again.rev, again.digest }, { "r1", first_digest }, "a failed seal changes nothing")

    -- json.memo changes the cost, not the bytes
    local plain_doc, memo_doc = sd.head("k", "/v"), sd.head("k", "/v")
    plain_doc.rules = { { id = "a" }, { id = "b" } }
    memo_doc.rules = json.memo({ { id = "a" }, { id = "b" } })
    eq(sd.seal(memo_doc, "r").digest, sd.seal(plain_doc, "r").digest, "same digest")
    eq(sd.encode(memo_doc), sd.encode(plain_doc), "same bytes")
  end

  -- ── rev_of ──
  local r1 = d.rev_of({ "a\tx", "b\ty" })
  ok(r1:match("^rev:%x%x%x%x%x%x$"), "rev: and 6 digits: " .. r1)
  eq(d.rev_of({ "b\ty", "a\tx" }), r1, "the order of the lines is no content")
  ok(d.rev_of({ "a\tx", "b\tz" }) ~= r1, "a changed version tag changes the rev")
  ok(d.rev_of({ "a\tx" }) ~= r1, "a missing line changes the rev")
  local given = { "b", "a" }
  d.rev_of(given)
  eq(given, { "b", "a" }, "the caller's list is not sorted in place")
  -- The rev is a hash of the sorted lines: the sort must be bytewise on every Lua (plain Lua 5.1 follows the
  -- locale with `<`, LuaJIT does not, so under LuaJIT only the spy on `table.sort` shows the difference).
  eq(
    d.rev_of({ "a", "B", "_", "Z", "b" }),
    "rev:" .. require("lib.nvim.fs.etag").sha256("B\nZ\n_\na\nb"):sub(1, 6),
    "the lines are hashed in byte order"
  )
  local real_sort, comparators = table.sort, {}
  rawset(table, "sort", function(t, cmp)
    comparators[#comparators + 1] = cmp or false
    return real_sort(t, cmp)
  end)
  local rev_ok, rev_err = pcall(d.rev_of, { "b\ty", "a\tx" })
  rawset(table, "sort", real_sort)
  ok(rev_ok, tostring(rev_err))
  eq(comparators, { json.bytes_less }, "sorted with the locale-independent comparator")

  -- ── encode: canonical bytes, and the limit ──
  local dd = fixed()
  eq(dd.encode({ b = 1, a = json.object({}) }), '{"a":{},"b":1}')
  eq(dd.encode({ a = { 1 } }, { indent = 2 }), '{\n  "a": [\n    1\n  ]\n}')
  dd.MAX_DOC_BYTES = 20
  local text, err = dd.encode({ kind = "tasks.snapshot", pad = ("x"):rep(50) })
  eq(text, nil)
  eq(err.code, "payload_too_large")
  eq(err.retryable, false)
  has(err.message, "more than the 20 the contract allows")
  has(err.message, "ask for a page or an area", "the default hint")
  eq(dd.encode({ kind = "tasks.x" }), '{"kind":"tasks.x"}', "18 bytes: under the limit of 20")
  eq(
    select(1, dd.encode({ kind = "tasks.xxx" })),
    '{"kind":"tasks.xxx"}',
    "exactly 20 bytes: still fine"
  )
  eq(select(1, dd.encode({ kind = "tasks.xxxx" })), nil, "21 bytes: over")
  local exempt = dd.encode({ kind = "tasks.error", pad = ("x"):rep(50) })
  ok(exempt and #exempt > 20, "an error document is exempt from the limit")
  local other_kind = dd.encode({ kind = "rules.error", pad = ("x"):rep(50) })
  eq(other_kind, nil, "only the error kind of THIS contract is exempt")
  local hinted =
    doc.new({ plugin = "x.nvim", schema = 1, max_bytes = 5, too_large_hint = "ask for less" })
  has(
    select(2, hinted.encode({ pad = "xxxxxxxx" })).message,
    "ask for less",
    "the hint is the plugin's"
  )
  -- a value JSON cannot hold is an internal error with the path, not a raise
  local bad, bad_err = dd.encode({ n = 0 / 0 })
  eq(bad, nil)
  eq(bad_err.code, "internal")
  eq(bad_err.retryable, false)
  has(bad_err.message, "$.n")

  -- ── relative / safe_path / redact: nothing of this machine in a document ──
  eq(
    d.relative("C:/Users/me/vault", "C:/Users/me/vault/lib.nvim/ROADMAP/tasks/x.md"),
    "lib.nvim/ROADMAP/tasks/x.md"
  )
  eq(
    d.relative("C:/Users/me/vault/", "C:\\Users\\me\\vault\\a.md"),
    "a.md",
    "backslashes, a trailing slash"
  )
  eq(d.relative("C:/Users/me/vault", "c:/users/ME/Vault/a.md"), "a.md", "case does not matter")
  eq(d.relative("C:/Users/me/vault", "C:/Users/me/vault2/a.md"), nil, "a longer name is not inside")
  eq(
    d.relative("C:/Users/me/vault", "C:/Users/me/vault"),
    nil,
    "the root itself has no relative path"
  )
  eq(d.relative("/a/b", "/c/d"), nil)
  -- the root may be spelled either way, with a trailing slash or several
  for _, root in ipairs({
    "C:\\Users\\me\\vault",
    "C:\\Users\\me/vault",
    "C:/Users/me/vault/",
    "C:/Users/me/vault//",
    "C:\\Users\\me\\vault\\",
  }) do
    eq(d.relative(root, "C:/Users/me/vault/a.md"), "a.md", root)
    eq(d.relative(root, "C:\\Users\\me\\vault\\a.md"), "a.md", root)
    eq(d.relative(root, "C:/Users/me/vault2/a.md"), nil, "a longer name is not inside: " .. root)
  end
  -- an empty root is no root (as for redact): nothing is inside it; `/` is the root of the file system
  eq(d.relative("", "/etc/passwd"), nil, "an empty root has nothing inside")
  eq(d.relative("", "rel/x.md"), nil)
  eq(d.relative("/", "/etc/passwd"), "etc/passwd", "the file system root is a root")

  eq(d.safe_path("/v", "/v/docs/shared.md"), "docs/shared.md", "inside: relative")
  eq(d.safe_path("/v", "docs/shared.md"), "docs/shared.md", "already relative: as it is")
  eq(d.safe_path("/v", "repo@abc1234"), "repo@abc1234", "a repo@commit is no path")
  eq(d.safe_path("/v", "/etc/secret.md"), "<external>/secret.md", "absolute POSIX")
  eq(d.safe_path("/v", "C:\\Users\\someone\\notes.md"), "<external>/notes.md", "a drive path")
  eq(d.safe_path("/v", "~/notes/n.md"), "<external>/n.md", "home")
  eq(d.safe_path("/v", "/etc/dir/"), "<external>/dir", "a trailing slash")
  -- no root known: an absolute path is external whatever its spelling, not "relative" with its slash cut off
  eq(
    d.safe_path("", "/home/me/secret/notes.md"),
    "<external>/notes.md",
    "no root: an absolute path is external"
  )
  eq(d.safe_path("", "C:/Users/me/x.md"), "<external>/x.md")
  eq(d.safe_path("", "~/x.md"), "<external>/x.md")
  eq(d.safe_path("", "rel/x.md"), "rel/x.md", "a relative path stays")
  eq(d.safe_path("/", "/etc/passwd"), "etc/passwd", "the file system root is still a root")
  eq(d.safe_path("/v", "/"), "<external>/", "a bare slash has no name")
  eq(d.safe_path("C:\\Users\\me\\vault\\", "C:/Users/me/vault/a.md"), "a.md", "a backslash root")

  -- `.` and `..` are resolved before the root is compared: a path that starts with the root and then climbs out of
  -- it is outside, and the document names it `<external>/<name>`
  eq(d.relative("/v", "/v/../etc/passwd"), nil, "climbing out of the root is outside")
  eq(d.relative("/v", "/v/a/../../w/x.md"), nil, "also further down")
  eq(d.relative("/v", "/v/a/../b.md"), "b.md", "a '..' that stays inside")
  eq(d.relative("/v", "/v/./a//b.md"), "a/b.md", "'.' and doubled slashes")
  eq(d.relative("/v/sub/..", "/v/a.md"), "a.md", "dots in the root too")
  eq(d.relative("C:/Users/me/vault", "C:/Users/me/vault/../other/x.md"), nil, "a drive path")
  eq(d.safe_path("/v", "/v/../etc/passwd"), "<external>/passwd", "safe_path: outside")
  eq(d.safe_path("/v", "/v/a/.."), "<external>/v", "the name of the folder it lands in")
  eq(d.safe_path("/v", "/v/a/./b.md"), "a/b.md", "safe_path: inside")
  eq(
    d.safe_path("/v", "docs/../x.md"),
    "docs/../x.md",
    "a relative text is not a path of this machine"
  )

  -- case beyond ASCII: NTFS treats Ö and ö as one letter, so a name with an umlaut must match whatever its case
  eq(d.relative("C:/Users/Jörg/vault", "C:/USERS/JÖRG/vault/x"), "x", "Ö and ö")
  eq(d.relative("C:/Users/JÖRG/vault", "c:/users/jörg/vault/x"), "x", "the other way round")
  eq(d.safe_path("C:/Users/Jörg/vault", "C:/USERS/JÖRG/vault/x"), "x", "not '<external>/x'")
  eq(
    d.relative("C:/Users/Jörg/vault", "C:/USERS/JÖRG/vaultx/x"),
    nil,
    "a longer name is not inside"
  )
  eq(d.relative("C:/Users/Jörg/vault", "D:/other/x"), nil)
  eq(
    d.relative("C:/Users/Jörg/vault", "C:/USERS/JÖRG/vault/Ünï"),
    "Ünï",
    "the rest is as it was"
  )
  -- a letter whose lower case is another length (Ⱥ 2 bytes -> ⱥ 3, İ 2 -> i 1) stays as it is: no shifted position
  eq(d.relative("C:/Ⱥ/Jörg", "C:/Ⱥ/JÖRG/f"), "f", "the same letter on both sides")
  eq(d.relative("C:/İ/Jörg", "C:/İ/JÖRG/f"), "f")
  eq(d.relative("C:/Ⱥ/Jörg", "C:/ⱥ/JÖRG/f"), nil, "but Ⱥ and ⱥ are not told apart")
  -- a byte that is no UTF-8 (a Latin-1 name) is no error
  eq(d.relative("C:/Users/J\233rg/vault", "C:/USERS/J\233RG/vault/x"), "x", "a stray byte")
  eq(d.relative("C:/Users/J\233rg/vault", "C:/USERS/J\195\169RG/vault/x"), nil, "and is not é")

  eq(
    d.redact("C:/Users/me/vault", "cannot read C:/Users/me/vault/a.md"),
    "cannot read <vault>/a.md"
  )
  eq(
    d.redact("C:/Users/me/vault", "cannot read C:\\Users\\me\\vault\\a.md"),
    "cannot read <vault>\\a.md",
    "the backslash spelling"
  )
  eq(
    d.redact("C:/Users/me/vault", "c:/USERS/me/VAULT and C:/Users/me/vault twice"),
    "<vault> and <vault> twice",
    "case, every place"
  )
  eq(d.redact("/v", "nothing to hide"), "nothing to hide")
  eq(
    d.redact("", "an empty root hides nothing"),
    "an empty root hides nothing",
    "and does not loop"
  )
  eq(
    fixed({ scope_key = "source" }).redact("/s", "in /s/x"),
    "in <source>/x",
    "the placeholder follows the scope key"
  )
  eq(fixed({ placeholder = "<root>" }).redact("/s", "in /s/x"), "in <root>/x", "or is named")
  eq(d.redact("/a.b", "x /a.b/c /aXb/c"), "x <vault>/c /aXb/c", "the root is text, not a pattern")

  -- the root is hidden whatever its spelling (a root from the environment or the working directory is not tidy)
  local both = "cannot read C:/Users/me/vault/a.md and C:\\Users\\me\\vault\\b.md"
  for _, root in ipairs({
    "C:/Users/me/vault",
    "C:\\Users\\me\\vault",
    "C:\\Users\\me/vault",
    "C:/Users/me\\vault",
    "C:/Users/me/vault/",
    "C:/Users/me/vault//",
    "C:\\Users\\me\\vault\\",
    "c:\\USERS\\me\\Vault",
  }) do
    eq(d.redact(root, both), "cannot read <vault>/a.md and <vault>\\b.md", root)
  end
  eq(
    d.redact("C:/Users/me/vault/", "in C:/Users/me/vault and C:/Users/me/vault/a.md"),
    "in <vault> and <vault>/a.md",
    "a trailing slash on the root does not eat the separator, and the bare root is hidden too"
  )
  eq(
    d.redact("C:/Users/me/vault", "a C:\\Users/me\\vault/x b"),
    "a <vault>/x b",
    "a message that mixes the slashes"
  )
  -- a POSIX root may hold a backslash in a name: it is read as a separator, and the same spelling in a message goes
  eq(
    d.redact("/home/a\\b/vault", "in /home/a\\b/vault/x and /home/a/b/vault/y"),
    "in <vault>/x and <vault>/y",
    "a literal backslash in the root"
  )
  eq(d.redact("/", "x/y"), "x/y", "the root of the file system has no name to hide")
  eq(d.redact("//", "x/y"), "x/y")
  eq(d.redact("C:/", "C:/Users/x"), "<vault>/Users/x", "a drive root hides the drive")
  eq(d.redact("vault", "a vault b"), "a <vault> b", "the placeholder is not searched again")
  eq(d.redact("aa", "aaaaa"), "<vault><vault>a", "hits do not overlap")
  eq(d.redact("c:/v", "C:/V C:/v"), "<vault> <vault>", "adjacent hits, every case")
  eq(d.redact("/v", "/v/x/v"), "<vault>/x<vault>", "a hit at the start and at the end")
  eq(
    d.redact("C:/Users/me/vault", ("C:/Users/me/vault/a c:\\USERS\\me\\vault\\b "):rep(3)),
    ("<vault>/a <vault>\\b "):rep(3),
    "many hits, mixed spelling and case"
  )
  -- Unicode letters (a user name with an umlaut), and what precedes a hit may change length when folded
  eq(
    d.redact("C:/Users/Jörg/vault", "in C:/USERS/JÖRG/vault/x here"),
    "in <vault>/x here",
    "Ö and ö"
  )
  eq(
    d.redact("C:/Users/JÖRG/vault", "in c:/users/jörg/vault/x here"),
    "in <vault>/x here",
    "ö in the message, Ö in the root"
  )
  eq(
    d.redact("C:/Users/Jörg/vault", "in C:\\USERS\\JÖRG\\vault\\x here"),
    "in <vault>\\x here",
    "the backslash spelling"
  )
  eq(
    d.redact("C:/Users/Jörg/vault", "C:/users/jörg/VAULT/a and C:/USERS/JÖRG/vault/b"),
    "<vault>/a and <vault>/b",
    "two hits"
  )
  eq(
    d.redact("C:/Users/Jörg/vault", "ȺİⱥK ÄÖÜ C:/USERS/JÖRG/vault/x İ"),
    "ȺİⱥK ÄÖÜ <vault>/x İ",
    "letters that change length before and after the hit leave the positions right"
  )
  eq(d.redact("C:/v", "x \233 C:/V/y \233"), "x \233 <vault>/y \233", "a stray byte is no error")

  -- the work follows the length of the text, not the number of hits (a request echoes up to 256 KiB into a message:
  -- the quadratic version held the editor for seconds)
  do
    local hits = 20000
    local started = vim.uv.hrtime()
    local hidden = d.redact("C:/Users/me/vault", ("C:/Users/me/vault "):rep(hits))
    local took_ms = (vim.uv.hrtime() - started) / 1e6
    eq(hidden, ("<vault> "):rep(hits), "every hit")
    ok(took_ms < 1000, ("%d hits took %.0f ms"):format(hits, took_ms))
    started = vim.uv.hrtime()
    hidden = d.redact("C:/Users/J\195\182rg/vault", ("c:\\users\\J\195\150rg\\vault "):rep(hits))
    took_ms = (vim.uv.hrtime() - started) / 1e6
    eq(hidden, ("<vault> "):rep(hits), "every hit, with a letter beyond ASCII")
    ok(took_ms < 1000, ("%d hits with an umlaut took %.0f ms"):format(hits, took_ms))
  end

  -- ── error_doc ──
  local e = fixed().error_doc(
    { code = "not_found", message = "no such file C:/v/x.md", retryable = false },
    "C:/v"
  )
  eq(e.kind, "tasks.error")
  eq(e.code, "not_found")
  eq(e.message, "no such file <vault>/x.md", "the root is hidden")
  eq(e.retryable, false)
  eq(e.details, nil)
  eq(e.vault.id, "v")
  eq(e.schema, 1)
  local e2 = fixed().error_doc({
    code = "conflict",
    message = "m",
    retryable = true,
    details = { id = "a/b" },
  })
  eq(e2.retryable, true)
  eq(e2.details, json.object({ id = "a/b" }))
  has(
    json.encode(fixed().error_doc({ code = "io", message = "m", details = {} })),
    '"details":{}',
    "empty details are an object, not a list"
  )
  eq(e2.message, "m", "no root: the message as it is")
  eq(e2.vault.id, "")
  eq(
    fixed().error_doc({ code = "io", message = "m", retryable = "yes" }).retryable,
    false,
    "only true is retryable"
  )
  -- a malformed error is made into a document, never a throw (the door promises that), with and without a root
  local ed = fixed()
  for _, root in ipairs({ "/v", "" }) do
    local label = "root '" .. root .. "'"
    local r = root ~= "" and root or nil
    eq(
      ed.error_doc({ code = "not_found" }, r).message,
      "not_found",
      "no message: the code, " .. label
    )
    eq(ed.error_doc({ code = "io", message = 5 }, r).message, "5", "a number: as text, " .. label)
    eq(
      ed.error_doc({ code = "io", message = {} }, r).message,
      "error value of type table",
      "a table: its type, never its address, " .. label
    )
    eq(ed.error_doc({ message = "m" }, r).message, "m", "no code: still the message, " .. label)
    -- a document always has a code a client can match: one that is no text is `internal`
    eq(ed.error_doc({ message = "m" }, r).code, "internal", "no code, " .. label)
    eq(ed.error_doc({ code = 5, message = "m" }, r).code, "internal", "a number as code, " .. label)
    eq(ed.error_doc({ code = {}, message = "m" }, r).code, "internal", "a table as code, " .. label)
    eq(ed.error_doc({ code = 5 }, r).message, "5", "and the message is that code, " .. label)
    eq(ed.error_doc({ code = "io", message = "m" }, r).code, "io", "a text stays, " .. label)
    eq(ed.error_doc("boom", r).code, "internal", "a text is an internal error, " .. label)
    eq(ed.error_doc("boom", r).message, "boom", label)
    eq(ed.error_doc(nil, r).message, "nil", label)
    eq(
      ed.error_doc({ code = "io", message = "m", details = "x" }, r).details,
      nil,
      "details that is no table is left out, " .. label
    )
    eq(
      ed.error_doc({ code = "io", message = "m", details = { id = "a" } }, r).details,
      json.object({ id = "a" }),
      "and a table stays, " .. label
    )
  end
  eq(
    ed.error_doc({ code = "io", message = 5 }, "/v").vault.id,
    "v",
    "the head is the same one with a coerced message"
  )
  ok(ed.encode(ed.error_doc({ code = "io", message = 5, details = "x" }, "/v")), "and it encodes")
  eq(
    ed.error_doc({ code = "io", message = "at C:/v/x" }, "C:/v").message,
    "at <vault>/x",
    "a message that is text is redacted as before"
  )
  eq(
    ed.error_doc({ code = "io", message = "at C:/v/x" }, "C:\\v\\").message,
    "at <vault>/x",
    "whatever the spelling of the root"
  )
  eq(
    json.encode(fixed().error_doc({ code = "internal", message = "boom", retryable = false })),
    '{"code":"internal","engine":{"git":"abc1234","nvim":"v0.11.0","version":"0.1.0"},"generated_at":"2026-01-01T00:00:00Z","kind":"tasks.error","message":"boom","plugin":"tasks.nvim","retryable":false,"schema":1,"vault":{"id":""}}',
    "the bytes of an error document"
  )
end
