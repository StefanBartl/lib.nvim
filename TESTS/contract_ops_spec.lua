-- TESTS/contract_ops_spec.lua -- lib.nvim.contract.ops: the write door of a machine contract.

return function(H)
  local ok = H.ok
  local doc = require("lib.nvim.contract.doc")
  local capi = require("lib.nvim.contract.api")
  local cops = require("lib.nvim.contract.ops")
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

  local function lacks(text, part, msg)
    ok(not text:find(part, 1, true), msg or ("unexpected " .. part))
  end

  local ROOT = "C:/Users/me/vault"

  local function new_doc()
    local d = doc.new({ plugin = "tasks.nvim", schema = 1 })
    d.clock = function()
      return "2026-01-01T00:00:00Z"
    end
    d.engine_info = function()
      return { version = "0.1.0", git = "abc1234", nvim = "v0.11.0" }
    end
    return d
  end

  local seen = {} -- what the handlers saw, in order

  ---@param extra? table  # overrides of the config
  local function new_door(extra)
    local d = new_doc()
    local cfg = {
      doc = d,
      order = { "set", "new", "boom", "nothing", "weird" },
      ops = {
        set = {
          fields = { id = "string", patch = "object", if_match = "string", expect = "object" },
          run = function(op, ctx)
            seen[#seen + 1] = { op = vim.deepcopy(op), ctx = ctx }
            if op.id == "bad" then
              return {
                ok = false,
                outcome = "failed",
                error = { code = "not_found", message = "no bad" },
              }
            end
            return { ok = true, outcome = "changed", id = op.id, changed_ids = { op.id } }
          end,
        },
        new = {
          fields = {
            title = "string",
            body = "string",
            tags = "strings",
            n = "integer",
            dry = "boolean",
            fields = "object",
          },
          run = function(op, ctx)
            seen[#seen + 1] = { op = vim.deepcopy(op), ctx = ctx }
            return { ok = true, outcome = "created" }
          end,
        },
        boom = {
          fields = {},
          run = function()
            error(
              "/home/me/.local/share/nvim/lazy/x.nvim/lua/x_nvim/a.lua:12: boom at "
                .. ROOT
                .. "/a.md"
            )
          end,
        },
        nothing = {
          fields = {},
          run = function() end,
        },
        weird = {
          fields = { v = "even" },
          run = function()
            return { ok = true, outcome = "changed" }
          end,
        },
      },
      types = {
        even = {
          label = "an even number",
          is = function(v)
            return type(v) == "number" and v % 2 == 0
          end,
        },
      },
      patterns = { { code = "not_found", find = { "unknown area" } } },
    }
    for k, v in pairs(extra or {}) do
      cfg[k] = v
    end
    return cops.make(cfg), d, cfg
  end

  local door, d = new_door()

  ---@param request table
  ---@return table|nil doc, table|nil err
  local function run(request, opts)
    return door.run(request, opts or { root = ROOT })
  end

  local function refused(request, code, part, msg)
    local result, err = run(request)
    eq(result, nil, (msg or "") .. ": no document")
    ok(err ~= nil, (msg or "") .. ": an error")
    eq(err.code, code, msg)
    if part then
      has(err.message, part, msg)
    end
    return err
  end

  -- ── make: a wrong config is refused where it is made, with the position of the caller ──
  local function refused_make(cfg, part)
    local good, err = pcall(cops.make, cfg)
    ok(not good, "expected make to refuse " .. vim.inspect(cfg))
    has(tostring(err), part)
  end
  refused_make(nil, "needs a table")
  refused_make({ ops = {} }, "doc must be")
  refused_make({ doc = {}, ops = {} }, "doc must be")
  refused_make({ doc = d }, "ops must be a table")
  refused_make({ doc = d, ops = { x = {} } }, "operation 'x' needs fields and run")
  refused_make({ doc = d, ops = { x = { fields = {} } } }, "operation 'x' needs fields and run")
  refused_make(
    { doc = d, ops = { x = { fields = { a = "strng" }, run = function() end } } },
    "unknown type 'strng'"
  )
  refused_make({ doc = d, ops = {}, context = 5 }, "context must be a function")
  refused_make({ doc = d, ops = {}, finish = "x" }, "finish must be a function")
  refused_make({ doc = d, ops = {}, types = { t = {} } }, "type 't' needs an `is` function")
  refused_make({ doc = d, ops = {}, patterns = { { code = 1, find = {} } } }, "patterns[1].code")
  ok(pcall(cops.make, { doc = d, ops = {} }), "no operations at all is a valid, if useless, door")

  -- ── the names ──
  eq(door.OPS, { "set", "new", "boom", "nothing", "weird" }, "the order the plugin gave")
  local sorted_door = new_door({ order = false })
  eq(
    sorted_door.OPS,
    { "boom", "new", "nothing", "set", "weird" },
    "default: byte order of the names"
  )
  eq(door.limits, { batch_ops = 100, client_op_id = 64 })

  -- ── the shape of a request, all of it, before anything runs ──
  refused(nil, "invalid_argument", "must be an object", "no request")
  refused("x", "invalid_argument", "must be an object", "a text as request")
  refused({}, "invalid_argument", "the list of operations is missing", "no ops")
  refused(
    { ops = "set" },
    "invalid_argument",
    "must be a list of operations",
    "ops that is no list"
  )
  refused(
    { ops = { set = {} } },
    "invalid_argument",
    "must be a list of operations",
    "ops that is a map"
  )
  refused({ ops = {} }, "invalid_argument", "the list of operations is empty", "empty ops")

  local many = {}
  for i = 1, 101 do
    many[i] = { op = "boom" }
  end
  local over = refused(
    { ops = many },
    "payload_too_large",
    "at most 100 operations in one request, got 101",
    "101 ops"
  )
  eq(over.retryable, false)
  many[101] = nil
  eq(select(2, run({ ops = many, dry_run = true })), nil, "exactly 100 operations are fine")
  seen = {}

  refused(
    { ops = { 5 } },
    "invalid_argument",
    "ops[1]: must be an object",
    "an operation that is no object"
  )
  refused(
    { ops = { { op = "set" }, "x" } },
    "invalid_argument",
    "ops[2]: must be an object",
    "the second one"
  )

  local unknown = refused(
    { ops = { { op = "explode" } } },
    "invalid_argument",
    'ops[1]: unknown operation "explode"',
    "unknown operation"
  )
  has(
    unknown.message,
    "(operations: set, new, boom, nothing, weird)",
    "named in the plugin's order"
  )
  has(
    refused({ ops = { { op = 5 } } }, "invalid_argument", nil, "numeric name").message,
    "unknown operation 5"
  )
  has(
    refused({ ops = { {} } }, "invalid_argument", nil, "no name").message,
    "unknown operation nil"
  )
  has(
    refused({ ops = { { op = { 1 } } } }, "invalid_argument", nil, "table name").message,
    "unknown operation <table>"
  )
  local long_name =
    refused({ ops = { { op = ("x"):rep(5000) } } }, "invalid_argument", nil, "a huge name")
  ok(#long_name.message < 300, "a long name is echoed short: " .. #long_name.message)

  local colour = refused(
    { ops = { { op = "set", colour = "red" } } },
    "invalid_argument",
    "ops[1] (set): unknown field 'colour'",
    "unknown field"
  )
  has(colour.message, "(fields: expect, id, if_match, patch)", "the fields, sorted")
  local long_field = refused(
    { ops = { { op = "set", [("f"):rep(5000)] = 1 } } },
    "invalid_argument",
    "unknown field",
    "a huge field name"
  )
  ok(#long_field.message < 300, "and so is a field name")
  has(
    refused({ ops = { { op = "set", [3] = 1 } } }, "invalid_argument", nil, "a key that is no text").message,
    "unknown field '3'"
  )

  -- types, each with its own words
  has(
    refused({ ops = { { op = "set", id = 7 } } }, "invalid_argument", nil, "id").message,
    "ops[1] (set): id must be text"
  )
  has(
    refused({ ops = { { op = "set", patch = { 1 } } } }, "invalid_argument", nil, "patch").message,
    "patch must be an object"
  )
  has(
    refused({ ops = { { op = "new", tags = 5 } } }, "invalid_argument", nil, "tags").message,
    "tags must be text or a list of text"
  )
  has(
    refused({ ops = { { op = "new", tags = { "a", 1 } } } }, "invalid_argument", nil, "tags list").message,
    "tags must be text or a list of text"
  )
  has(
    refused({ ops = { { op = "new", n = 0 } } }, "invalid_argument", nil, "n=0").message,
    "n must be a whole number from 1"
  )
  has(
    refused({ ops = { { op = "new", n = 1.5 } } }, "invalid_argument", nil, "n=1.5").message,
    "n must be a whole number from 1"
  )
  has(
    refused({ ops = { { op = "new", n = 1e6 } } }, "invalid_argument", nil, "n=1e6").message,
    "n must be a whole number from 1"
  )
  has(
    refused({ ops = { { op = "new", dry = "yes" } } }, "invalid_argument", nil, "boolean").message,
    "dry must be true or false"
  )
  has(
    refused({ ops = { { op = "weird", v = 3 } } }, "invalid_argument", nil, "plugin type").message,
    "v must be an even number"
  )
  seen = {}
  local accepted =
    run({ ops = { { op = "new", tags = "a", n = 999999, dry = false, fields = {}, body = "" } } })
  eq(accepted.ok, true, "the edges of the types are accepted")
  eq(
    run({ ops = { { op = "set", id = vim.NIL, patch = vim.NIL } } }).ok,
    true,
    "a JSON null is no wrong type"
  )
  seen = {}

  -- two faults: the same one every time (alphabetical), and the first operation's
  local two = refused(
    { ops = { { op = "set", zeta = 1, alpha = 2, id = 5 } } },
    "invalid_argument",
    "unknown field 'alpha'",
    "two faults"
  )
  eq(two.message, "ops[1] (set): unknown field 'alpha' (fields: expect, id, if_match, patch)")
  has(
    refused({ ops = { { op = "set", id = 5, patch = 5 } } }, "invalid_argument", nil, "two types").message,
    "id must be text",
    "id before patch"
  )
  has(
    refused(
      { ops = { { op = "set", id = "ok" }, { op = "nope" }, { op = "set", id = 5 } } },
      "invalid_argument",
      nil,
      "ops"
    ).message,
    "ops[2]: unknown operation",
    "the first operation with a fault"
  )
  eq(#seen, 0, "a request with a fault runs NOTHING")

  -- client_op_id and dry_run
  for _, bad in ipairs({ "", "a b", ("x"):rep(65), "a/b", "ü", 5, true, {} }) do
    has(
      refused(
        { ops = { { op = "boom" } }, client_op_id = bad },
        "invalid_argument",
        nil,
        "client_op_id " .. vim.inspect(bad)
      ).message,
      "client_op_id must be 1 to 64 characters of letters, digits and . _ : -"
    )
  end
  eq(
    select(2, run({ ops = { { op = "nothing" } }, client_op_id = ("x"):rep(64) })),
    nil,
    "64 characters are fine"
  )
  eq(
    select(2, run({ ops = { { op = "nothing" } }, client_op_id = "a.b_c:d-1" })),
    nil,
    "the allowed punctuation"
  )
  has(
    refused({ ops = { { op = "boom" } }, dry_run = "yes" }, "invalid_argument", nil, "dry_run").message,
    "dry_run must be true or false"
  )
  local narrow = new_door({ limits = { batch_ops = 2, client_op_id = 5 } })
  eq(
    select(
      2,
      narrow.run({ ops = { { op = "boom" }, { op = "boom" }, { op = "boom" } } }, { root = ROOT })
    ).code,
    "payload_too_large",
    "the limits are the plugin's"
  )
  has(
    select(2, narrow.run({ ops = { { op = "boom" } }, client_op_id = "abcdef" }, { root = ROOT })).message,
    "1 to 5 characters"
  )

  -- ── run: the answer ──
  seen = {}
  local result, rerr = run({
    client_op_id = "c-1",
    ops = {
      { op = "set", id = "a/b", patch = { prio = 1 } },
      { op = "set", id = "bad" },
      { op = "new", title = "T" },
    },
  })
  eq(rerr, nil)
  eq(result.kind, "tasks.result", "the kind is the plugin's")
  eq(result.client_op_id, "c-1", "echoed")
  eq(result.dry_run, false)
  eq(result.ok, false, "one failed entry: not ok, and never 'ok' for a part")
  eq(result.vault.id, "vault")
  eq(result.generated_at, "2026-01-01T00:00:00Z")
  ok(result.digest:match("^sha256:%x+$"), "sealed")
  eq(result.rev, nil, "no rev")
  eq(result.finish_error, nil)
  eq(#result.results, 3, "every operation has its entry, a failed one does not stop the others")
  eq({
    result.results[1].n,
    result.results[1].op,
    result.results[1].ok,
    result.results[1].changed_ids,
  }, { 1, "set", true, { "a/b" } })
  eq(
    { result.results[2].n, result.results[2].ok, result.results[2].error.code },
    { 2, false, "not_found" }
  )
  eq(result.results[2].changed_ids, {}, "changed_ids defaults to an empty list")
  eq(
    { result.results[3].n, result.results[3].op, result.results[3].outcome },
    { 3, "new", "created" }
  )
  eq(#seen, 3, "all three ran")
  ok(seen[1].ctx == seen[2].ctx and seen[2].ctx == seen[3].ctx, "one ctx for the request")
  eq(seen[1].ctx.root, ROOT, "the default context")
  eq(seen[1].ctx.dry, false)
  eq(json.encode(result.results[1].changed_ids), '["a/b"]')

  local all_ok = run({ ops = { { op = "set", id = "x" }, { op = "new", title = "T" } } })
  eq(all_ok.ok, true, "all entries ok")
  eq(all_ok.client_op_id, nil)

  -- a JSON null of a field is the same as leaving it out, for the handler too
  seen = {}
  run({ ops = { { op = "set", id = "x", patch = vim.NIL, if_match = vim.NIL } } })
  eq(seen[1].op, { op = "set", id = "x" }, "null fields are gone before the handler")

  -- dry run
  seen = {}
  local dry = run({ dry_run = true, ops = { { op = "set", id = "x" } } })
  eq(dry.dry_run, true)
  eq(seen[1].ctx.dry, true, "told to the handlers")

  -- ── the context hook ──
  local ctx_params, ctx_opts
  local hooked = new_door({
    context = function(params, opts)
      ctx_params, ctx_opts = params, opts
      return { root = opts.root, today = "2026-10-14" }
    end,
  })
  seen = {}
  hooked.run({ ops = { { op = "set", id = "x" } } }, { root = ROOT, extra = 1 })
  eq(ctx_opts.extra, 1, "the hook gets the options")
  eq(#ctx_params.ops, 1, "and the request")
  eq(seen[1].ctx.today, "2026-10-14", "the handler gets what the hook built")
  eq(seen[1].ctx.dry, false, "plus dry")

  local no_vault = new_door({
    context = function()
      return nil, { code = "not_found", message = "vault not found", retryable = false }
    end,
  })
  seen = {}
  local nd, ne = no_vault.run({ ops = { { op = "set", id = "x" } } }, { root = ROOT })
  eq(nd, nil)
  eq(ne.code, "not_found", "a context that cannot be had refuses the request")
  eq(#seen, 0)
  local shape_first = no_vault.run({ ops = {} }, { root = ROOT })
  eq(shape_first, nil)
  eq(
    select(2, no_vault.run({ ops = {} }, { root = ROOT })).code,
    "invalid_argument",
    "the shape is judged before the context"
  )
  local bare_ctx = new_door({
    context = function()
      return nil
    end,
  })
  eq(
    select(2, bare_ctx.run({ ops = { { op = "boom" } } })).code,
    "internal",
    "no context and no reason"
  )
  local text_ctx = new_door({
    context = function()
      return 5
    end,
  })
  eq(
    select(2, text_ctx.run({ ops = { { op = "boom" } } })).code,
    "internal",
    "a context that is no table"
  )

  -- ── a handler never takes the door down ──
  seen = {}
  local mixed = run({ ops = { { op = "boom" }, { op = "nothing" }, { op = "set", id = "after" } } })
  eq(mixed.ok, false)
  local boom = mixed.results[1]
  eq(
    { boom.ok, boom.outcome, boom.error.code, boom.n, boom.op },
    { false, "failed", "internal", 1, "boom" }
  )
  has(boom.error.message, "x_nvim/a.lua:12: boom at <vault>/a.md", "scrubbed, and the root hidden")
  lacks(boom.error.message, "/home/me", "no path of this machine")
  eq(mixed.results[2].error.code, "internal", "a handler that answers nothing")
  has(mixed.results[2].error.message, "answered nothing")
  eq(mixed.results[3].ok, true, "the operation after them still ran")
  eq(#seen, 1)

  local raises_table = new_door({
    ops = {
      t = {
        fields = {},
        run = function()
          error({ code = "x" })
        end,
      },
    },
  })
  local tr = raises_table.run({ ops = { { op = "t" } } }, { root = ROOT })
  has(tr.results[1].error.message, "error value of type table", "a raised table is no address")

  -- ── finish ──
  local finish_calls, finish_seen = 0, nil
  local with_finish = new_door({
    finish = function(ctx, results)
      finish_calls = finish_calls + 1
      finish_seen = { ctx = ctx, n = #results }
      for _, entry in ipairs(results) do
        if entry.ok then
          entry.index = json.object({ action = "written" })
        end
      end
    end,
  })
  local fin = with_finish.run(
    { ops = { { op = "set", id = "a" }, { op = "set", id = "bad" } } },
    { root = ROOT }
  )
  eq(finish_calls, 1, "once, after the last operation")
  eq(finish_seen.n, 2)
  eq(finish_seen.ctx.dry, false)
  eq(fin.results[1].index, json.object({ action = "written" }), "it may change the entries")
  eq(fin.results[2].index, nil)
  with_finish.run({ dry_run = true, ops = { { op = "set", id = "a" } } }, { root = ROOT })
  eq(finish_calls, 2, "also on a dry run: it looks at ctx.dry itself")
  eq(finish_seen.ctx.dry, true)

  local failing_finish = new_door({
    finish = function()
      error("cannot write the index in " .. ROOT .. "/a")
    end,
  })
  local ff = failing_finish.run({ ops = { { op = "set", id = "a" } } }, { root = ROOT })
  eq(ff.ok, false, "a finish that fails is not ok")
  has(ff.finish_error, "cannot write the index in <vault>/a", "and says why, the root hidden")
  eq(ff.results[1].ok, true, "the entries stay as they were")

  -- ── a document that cannot be sealed is an error, not a throw ──
  local nan = new_door({
    ops = {
      n = {
        fields = {},
        run = function()
          return { ok = true, value = 0 / 0 }
        end,
      },
    },
  })
  local nd2, ne2 = nan.run({ ops = { { op = "n" } } }, { root = ROOT })
  eq(nd2, nil)
  eq(ne2.code, "internal")
  has(ne2.message, "$.results[1].value", "the path in the document")

  -- ── failure / refuse ──
  local f = door.failure(ROOT, "unknown area 'x' in C:/Users/me/vault/x", nil)
  eq({ f.ok, f.outcome, f.error.code }, { false, "failed", "not_found" }, "the plugin's patterns")
  eq(f.error.message, "unknown area 'x' in <vault>/x", "the root hidden")
  local fi =
    door.failure(ROOT, "changed", { code = "conflict", id = "a", expected = "1", path = "/secret" })
  eq(fi.error.code, "conflict")
  eq(fi.error.details, json.object({ id = "a", expected = "1" }), "details are an object, no path")
  eq(door.failure(nil, "plain").error.message, "plain", "no root: as it is")
  eq(
    door.failure(ROOT, { code = "io", message = 7 }).error.message,
    "7",
    "a message that is no text"
  )
  eq(door.failure(ROOT, nil).error.code, "internal")
  local rf = door.refuse("invalid_argument", "nope", { id = "a" })
  eq(rf, {
    ok = false,
    outcome = "failed",
    error = {
      code = "invalid_argument",
      message = "nope",
      retryable = false,
      details = json.object({ id = "a" }),
    },
  })
  eq(door.refuse("io", "m").error.details, nil)
  has(
    json.encode(door.refuse("io", "m", {})),
    '"details":{}',
    "empty details are an object, not a list"
  )
  has(
    json.encode(door.failure(ROOT, { code = "io", message = "m", details = {} })),
    '"details":{}',
    "also in a failure"
  )

  -- the names are ordered by byte value, not by the language's `<` (which follows the locale on plain Lua 5.1)
  local real_sort, sort_calls = table.sort, {}
  H.with_patched(table, "sort", function(list, less)
    sort_calls[#sort_calls + 1] = less ~= nil
    return real_sort(list, less)
  end, function()
    local unordered = new_door({ order = false })
    eq(unordered.OPS, { "boom", "new", "nothing", "set", "weird" })
    unordered.check_shape({ ops = { { op = "set", zeta = 1, alpha = 2 } } })
  end)
  ok(#sort_calls >= 2, "the names and the fields are sorted: " .. #sort_calls)
  for i, with_comparator in ipairs(sort_calls) do
    ok(with_comparator, "sort #" .. i .. " uses the bytewise comparator, not the language's `<`")
  end

  -- ── guards ──
  for _, text in ipairs({
    "a\27b",
    "a\0b",
    "a\127b",
    "\1",
    "a\194\155b",
    "a\226\128\168b",
    "a\226\128\169b",
    "\8",
    "\11",
    "\31",
  }) do
    ok(cops.has_control(text), "control: " .. vim.inspect(text))
  end
  for _, text in ipairs({
    "plain",
    "tab\there",
    "line\nfeed",
    "ü日本\240\159\152\128",
    "\194\160",
    "",
  }) do
    ok(not cops.has_control(text), "fine: " .. vim.inspect(text))
  end
  ok(cops.has_control({ "ok", "bad\27" }), "a list is searched")
  ok(not cops.has_control({ "ok", "fine" }))
  ok(not cops.has_control(vim.NIL), "vim.NIL")
  ok(not cops.has_control(5), "a number")
  ok(
    cops.too_long("abcd", 3) and not cops.too_long("abc", 3),
    "characters, not bytes: " .. tostring(cops.too_long("ü日", 2))
  )
  ok(not cops.too_long("ü日", 2) and cops.too_long("ü日本", 2))
  ok(not cops.too_long(5, 1), "a non-text is not too long")

  -- ── through the door of the contract: contract.api ──
  local e2e_doc = new_doc()
  local e2e_door = cops.make({
    doc = e2e_doc,
    ops = {
      set = {
        fields = { id = "string", patch = "object" },
        run = function(op)
          return { ok = true, outcome = "changed", id = op.id, patch = op.patch }
        end,
      },
    },
  })
  local api = capi.make({ doc = e2e_doc, methods = { ops = e2e_door.method() } })
  local method = e2e_door.method()
  eq({ method.flat, method.keep_null }, { true, true })
  eq(method.params, { client_op_id = "string", dry_run = "boolean", ops = "object_list" })
  local text, code = api.call(
    "ops",
    '{"client_op_id":"c-1","dry_run":true,"ops":[{"op":"set","id":"a","patch":{"x":null}}]}',
    { root = ROOT }
  )
  eq(code, nil)
  local back = vim.json.decode(text)
  eq({ back.kind, back.client_op_id, back.dry_run, back.ok }, { "tasks.result", "c-1", true, true })
  eq(
    back.results[1].patch,
    { x = vim.NIL },
    "a null in a patch reaches the handler as vim.NIL: it means remove"
  )
  has(text, '"patch":{"x":null}', "and goes back out as null")
  local bad_text, bad_code = api.call("ops", '{"ops":[{"op":"explode"}]}', { root = ROOT })
  eq(bad_code, "invalid_argument", "a refused shape is an error document")
  has(vim.json.decode(bad_text).message, 'unknown operation "explode"')
  eq(
    select(2, api.call("ops", '{"ops":[],"extra":1}', { root = ROOT })),
    "invalid_argument",
    "unknown request field"
  )
  eq(
    select(2, api.call("ops", '{"ops":[{"op":"set"}],"dry_run":"yes"}', { root = ROOT })),
    "invalid_argument",
    "dry_run typed by the door of the api"
  )

  -- the order of the faults of one request does not depend on how the table was built
  local a = door.check_shape({ ops = { { op = "set", zeta = 1, alpha = 2, mike = 3 } } })
  local b = door.check_shape({ ops = { { op = "set", mike = 3, alpha = 2, zeta = 1 } } })
  eq(a.message, b.message, "the same fault every time")
end
