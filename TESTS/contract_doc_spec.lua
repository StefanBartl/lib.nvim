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
    local good, err = pcall(doc.new, cfg)
    ok(not good, "expected an error for " .. vim.inspect(cfg))
    has(tostring(err), part)
  end
  refused(nil, "needs a table")
  refused({ schema = 1 }, "plugin")
  refused({ plugin = "", schema = 1 }, "plugin")
  refused({ plugin = "x.nvim" }, "schema")
  refused({ plugin = "x.nvim", schema = 0 }, "schema")
  refused({ plugin = "x.nvim", schema = 1.5 }, "schema")
  refused({ plugin = "x.nvim", schema = "1" }, "schema")

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
  local info = real.engine_info()
  eq(info.version, "0.0.0")
  eq(info.git, "unknown", "without plugin_root git is never asked")
  ok(info.nvim:match("^v?%d+%.%d+"), "the nvim version: " .. info.nvim)

  -- ── engine_info: the commit of the plugin checkout ──
  ---Run `fn(git, calls)` with an instance whose plugin_root is set and a scripted `vim.system`.
  ---@param script (table|string)[]  per call: `{ code, signal, stdout }`, or a string = the start fails with it
  local function with_script(script, fn)
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
          return { code = step[1], signal = step[2], stdout = step[3] or "" }
        end,
      }
    end
    local instance =
      doc.new({ plugin = "tasks.nvim", schema = 1, plugin_root = "/opt/plugins/tasks.nvim/" })
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
      { "git", "-C", "/opt/plugins/tasks.nvim", "rev-parse", "--short", "HEAD" },
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
  with_script({ { 0, 0, "fatal: not a hash\n" }, { 0, 0, "ccc3333\n" } }, function(git, calls)
    eq(git(), "unknown")
    eq(git(), "unknown")
    eq(#calls, 1, "an answer of git that is not a commit is an answer: kept")
  end)
  -- without plugin_root git is never started
  do
    local real_system = vim.system
    local started = 0
    vim.system = function()
      started = started + 1
      error("must not start git")
    end
    local no_root = doc.new({ plugin = "tasks.nvim", schema = 1 })
    local git = no_root.engine_info().git
    no_root.engine_info()
    vim.system = real_system
    eq(git, "unknown")
    eq(started, 0, "no checkout named: no process")
  end
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

  -- ── rev_of ──
  local r1 = d.rev_of({ "a\tx", "b\ty" })
  ok(r1:match("^rev:%x%x%x%x%x%x$"), "rev: and 6 digits: " .. r1)
  eq(d.rev_of({ "b\ty", "a\tx" }), r1, "the order of the lines is no content")
  ok(d.rev_of({ "a\tx", "b\tz" }) ~= r1, "a changed version tag changes the rev")
  ok(d.rev_of({ "a\tx" }) ~= r1, "a missing line changes the rev")
  local given = { "b", "a" }
  d.rev_of(given)
  eq(given, { "b", "a" }, "the caller's list is not sorted in place")

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

  eq(d.safe_path("/v", "/v/docs/shared.md"), "docs/shared.md", "inside: relative")
  eq(d.safe_path("/v", "docs/shared.md"), "docs/shared.md", "already relative: as it is")
  eq(d.safe_path("/v", "repo@abc1234"), "repo@abc1234", "a repo@commit is no path")
  eq(d.safe_path("/v", "/etc/secret.md"), "<external>/secret.md", "absolute POSIX")
  eq(d.safe_path("/v", "C:\\Users\\someone\\notes.md"), "<external>/notes.md", "a drive path")
  eq(d.safe_path("/v", "~/notes/n.md"), "<external>/n.md", "home")
  eq(d.safe_path("/v", "/etc/dir/"), "<external>/dir", "a trailing slash")

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
  eq(
    json.encode(fixed().error_doc({ code = "internal", message = "boom", retryable = false })),
    '{"code":"internal","engine":{"git":"abc1234","nvim":"v0.11.0","version":"0.1.0"},"generated_at":"2026-01-01T00:00:00Z","kind":"tasks.error","message":"boom","plugin":"tasks.nvim","retryable":false,"schema":1,"vault":{"id":""}}',
    "the bytes of an error document"
  )
end
