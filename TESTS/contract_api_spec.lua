-- TESTS/contract_api_spec.lua -- lib.nvim.contract.api: the one door of a machine contract, never a throw.

return function(H)
  local ok = H.ok
  local doc = require("lib.nvim.contract.doc")
  local capi = require("lib.nvim.contract.api")
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

  ---@return table d  # a doc instance with fixed time and engine
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

  local seen -- what the last `run` saw

  ---@param d table
  ---@param extra? table
  local function new_api(d, extra)
    local methods = {
      hello = {
        params = {},
        run = function(_, opts)
          seen = { opts = opts }
          return d.head("tasks.hello", opts.root)
        end,
      },
      list = {
        params = { area = "string", status = "string_list", limit = "integer", offset = "integer" },
        run = function(params, opts)
          seen = { params = params, opts = opts }
          if params.limit and (params.limit < 1 or params.limit > 100) then
            return nil,
              { code = "invalid_argument", message = "limit out of range", retryable = false }
          end
          if params.area == "nope" then
            return nil, "unknown area 'nope' in " .. ROOT .. "/nope"
          end
          local out = d.head("tasks.list", opts.root)
          out.params = json.object(params)
          return out
        end,
      },
      task = {
        params = { id = "string" },
        required = { "id" },
        run = function(params, opts)
          return { kind = "tasks.task", id = params.id, root = opts.root }
        end,
      },
      ops = {
        flat = true,
        keep_null = true,
        params = { client_op_id = "string", dry_run = "boolean", ops = "object_list" },
        run = function(params)
          seen = { params = params }
          return { kind = "tasks.result", ok = true }
        end,
      },
      boom = {
        params = {},
        run = function()
          error(
            "/home/me/.local/share/nvim/lazy/x.nvim/lua/x_nvim/a.lua:12: boom at "
              .. ROOT
              .. "/a.md"
          )
        end,
      },
      silent = {
        params = {},
        run = function()
          return nil, nil
        end,
      },
      tabled = {
        params = {},
        run = function()
          return nil,
            { code = "conflict", message = "changed", retryable = true, details = { id = "a" } }
        end,
      },
      nan = {
        params = {},
        run = function()
          return { kind = "tasks.nan", n = 0 / 0 }
        end,
      },
      big = {
        params = {},
        run = function()
          return { kind = "tasks.big", pad = ("x"):rep(500) }
        end,
      },
      typed = {
        params = { n = "even", o = "object", f = "number", ol = "object_list" },
        run = function(params)
          return { kind = "tasks.typed", n = params.n }
        end,
      },
    }
    local cfg = {
      doc = d,
      methods = methods,
      engine_opts = { "root", "today" },
      patterns = { { code = "not_found", find = { "unknown area" } } },
      types = {
        even = function(v)
          return type(v) == "number" and v % 2 == 0
        end,
      },
    }
    for k, v in pairs(extra or {}) do
      cfg[k] = v
    end
    return capi.make(cfg)
  end

  local d = new_doc()
  local api = new_api(d)

  ---@param name string
  ---@param request any
  ---@param opts? table
  local function call(name, request, opts)
    local text, code = api.call(name, request, opts or { root = ROOT })
    return vim.json.decode(text), code, text
  end

  -- ── an answer ──
  local hello, code, text = call("hello")
  eq(code, nil, "no code for an answer")
  eq(hello.kind, "tasks.hello")
  eq(hello.vault.id, "vault")
  eq(hello.generated_at, "2026-01-01T00:00:00Z")
  eq(seen.opts, { root = ROOT }, "run gets the engine options")
  eq(text:sub(1, 1), "{", "the canonical bytes of the document")
  lacks(text, "\n", "compact")
  has(
    (api.call("hello", nil, { root = ROOT, indent = 2 })),
    '\n  "engine"',
    "indent makes it readable"
  )
  eq(select(2, api.call("hello")), nil)

  -- only the listed options reach run
  api.call("hello", nil, { root = ROOT, today = "2026-02-02", secret = "x" })
  eq(seen.opts, { root = ROOT, today = "2026-02-02" }, "engine_opts is a list of keys")

  -- ── the methods ──
  eq(
    api.methods(),
    { "big", "boom", "hello", "list", "nan", "ops", "silent", "tabled", "task", "typed" }
  )
  ok(
    api.METHODS.hello ~= nil and api.METHODS.hello.params ~= nil,
    "METHODS is the table of the plugin"
  )
  eq(api.MAX_REQUEST_BYTES, 256 * 1024)

  -- ── request forms ──
  eq(call("list", nil).kind, "tasks.list", "no request")
  eq(call("list", "").kind, "tasks.list", "an empty request is an empty request")
  eq(call("list", "  \n ").kind, "tasks.list", "blanks")
  eq(call("list", { params = { limit = 5 } }).params.limit, 5, "an already decoded request")
  eq(call("list", '{"schema":1,"params":{}}').kind, "tasks.list")
  eq(call("list", '{"schema":null,"params":null}').kind, "tasks.list", "a top-level null is absent")
  eq(
    call("list", '{"params":{"area":"x","status":["open","doing"],"limit":5,"offset":0}}').params,
    { area = "x", status = { "open", "doing" }, limit = 5, offset = 0 }
  )
  eq(seen.params.limit, 5)

  ---@return table doc, string|nil code
  local function refused(name, request, expected, msg)
    local e, c, t = call(name, request)
    eq({ e.kind, e.code, c }, { "tasks.error", expected, expected }, msg)
    eq(e.schema, 1)
    eq(type(e.retryable), "boolean")
    lacks(t, ROOT, msg .. ": no path of this machine")
    return e
  end

  local unknown = refused("frobnicate", nil, "not_found", "unknown method")
  has(unknown.message, "unknown method 'frobnicate'")
  has(unknown.message, "big, boom, hello, list", "it lists the methods, sorted")
  has(refused(42, nil, "not_found", "a method that is no text").message, "unknown method '42'")
  refused("list", "{nope", "invalid_argument", "bad JSON")
  refused("list", "[1,2]", "invalid_argument", "a request that is a list")
  refused("list", "5", "invalid_argument", "a request that is a number")
  refused("list", '"text"', "invalid_argument", "a request that is a string")
  refused("list", '{"schema":0}', "invalid_argument", "schema 0")
  refused("list", '{"schema":"1"}', "invalid_argument", "schema that is no number")
  refused("list", '{"params":[1]}', "invalid_argument", "params that is a list")
  refused("list", '{"params":5}', "invalid_argument", "params that is a number")
  local high = refused("list", '{"schema":2}', "unsupported_schema", "a higher schema")
  has(high.message, "asks for schema 2, this engine speaks 1")
  eq(high.retryable, false)
  local extra = refused("list", '{"extra":1}', "invalid_argument", "an unknown request field")
  has(extra.message, "unknown field 'extra' in the request (fields: schema, params)")
  local flat =
    refused("ops", '{"extra":1}', "invalid_argument", "an unknown field of a flat method")
  has(
    flat.message,
    "(fields: schema, client_op_id, dry_run, ops)",
    "a flat method names its own fields, sorted"
  )
  local unk =
    refused("list", '{"params":{"colour":"red"}}', "invalid_argument", "an unknown parameter")
  has(unk.message, "list takes no parameter 'colour' (parameters: area, limit, offset, status)")
  local none_known = refused("hello", '{"params":{"x":1}}', "invalid_argument", "hello takes none")
  eq(
    none_known.message,
    "hello takes no parameter 'x'",
    "no list of parameters when there are none"
  )
  has(
    refused("list", '{"params":{"limit":"5"}}', "invalid_argument", "a wrong type").message,
    "parameter 'limit' must be integer"
  )
  has(
    refused("list", '{"params":{"limit":5.5}}', "invalid_argument", "a fraction").message,
    "must be integer"
  )
  has(
    refused("list", '{"params":{"status":"open"}}', "invalid_argument", "a string for a list").message,
    "must be string list"
  )
  has(
    refused("list", '{"params":{"status":[1]}}', "invalid_argument", "a list of numbers").message,
    "must be string list"
  )
  has(
    refused("ops", '{"ops":[1]}', "invalid_argument", "a list of numbers").message,
    "must be object list"
  )
  has(
    refused("ops", '{"ops":[[1]]}', "invalid_argument", "a list of lists").message,
    "must be object list"
  )
  has(
    refused("ops", '{"dry_run":"yes"}', "invalid_argument", "a text for a boolean").message,
    "must be boolean"
  )
  eq(call("ops", '{"ops":[{"op":"x"},{}]}').ok, true, "objects, also empty ones")

  -- the code is also the second return value, and a refusal never raises
  eq(select(2, api.call("list", "{nope", { root = ROOT })), "invalid_argument")

  -- ── required parameters ──
  local req = refused("task", nil, "invalid_argument", "task without an id")
  eq(req.message, "task needs the parameter id")
  refused("task", '{"params":{}}', "invalid_argument", "task with empty params")
  eq(call("task", '{"params":{"id":"a/b"}}').id, "a/b")
  has(
    refused("task", '{"params":{"nope":1}}', "invalid_argument", "unknown before required").message,
    "takes no parameter 'nope'",
    "a parameter the method does not know is told before a missing one"
  )

  -- ── a flat method and null ──
  call(
    "ops",
    '{"schema":1,"client_op_id":"c-1","dry_run":true,"ops":[{"op":"set","patch":{"a":null}}]}'
  )
  eq(seen.params.client_op_id, "c-1")
  eq(seen.params.dry_run, true)
  eq(seen.params.schema, nil, "schema is not a parameter")
  eq(
    seen.params.ops[1].patch.a,
    vim.NIL,
    "keep_null: a null in a patch stays vim.NIL (it means remove)"
  )
  call("list", '{"params":{"area":null,"limit":null}}')
  eq(seen.params, {}, "otherwise a null is absent")
  seen = nil
  eq(
    call("ops", '{"client_op_id":null,"ops":[{"op":"x"}]}').kind,
    "tasks.result",
    "a top-level null of a flat method is no wrong type"
  )
  eq(seen.params.client_op_id, nil, "it is absent")
  eq(seen.params.ops[1].op, "x")

  -- the fields of a flat method are told sorted, whatever order the table holds them in
  local spread = capi.make({
    doc = d,
    methods = {
      wide = {
        flat = true,
        params = {
          zulu = "string",
          alpha = "string",
          mike = "string",
          bravo = "string",
          yankee = "string",
          charlie = "string",
          x_ray = "string",
        },
        run = function()
          return { kind = "tasks.wide" }
        end,
      },
    },
  })
  has(
    vim.json.decode((spread.call("wide", '{"extra":1}', { root = ROOT }))).message,
    "(fields: schema, alpha, bravo, charlie, mike, x_ray, yankee, zulu)",
    "sorted"
  )

  -- ── the size of a request ──
  local tight = capi.make({
    doc = d,
    max_request_bytes = 20,
    methods = {
      m = {
        params = { a = "string" },
        run = function()
          return { kind = "tasks.m" }
        end,
      },
    },
  })
  eq(tight.MAX_REQUEST_BYTES, 20, "the plugin's own limit")
  eq(select(2, tight.call("m", '{"params":{"a":"0123456789"}}')), "payload_too_large")
  eq(select(2, tight.call("m", '{"params":{}}')), nil, "and under it is fine")
  local huge = refused(
    "list",
    string.rep(" ", 300 * 1024) .. "{}",
    "payload_too_large",
    "a request over 256 KiB"
  )
  has(huge.message, "at most 262144 bytes")
  api.MAX_REQUEST_BYTES = 10
  refused("list", '{"params":{}}', "payload_too_large", "the limit is read at call time")
  eq(call("list", { params = {} }).kind, "tasks.list", "an already decoded request has no size")
  api.MAX_REQUEST_BYTES = 256 * 1024

  -- ── what run answers ──
  local bad_limit =
    refused("list", '{"params":{"limit":101}}', "invalid_argument", "run refuses with a table")
  eq(bad_limit.message, "limit out of range")
  local not_found = refused(
    "list",
    '{"params":{"area":"nope"}}',
    "not_found",
    "a text becomes a code by the patterns"
  )
  has(not_found.message, "unknown area 'nope' in <vault>/nope", "and the root is hidden")
  local t = refused("tabled", nil, "conflict", "a table keeps its code")
  eq(t.retryable, true)
  eq(t.details, { id = "a" })
  local none = refused("silent", nil, "internal", "nil and no error")
  eq(none.message, "nil")

  local boom = refused("boom", nil, "internal", "run raises")
  has(
    boom.message,
    "x_nvim/a.lua:12: boom at <vault>/a.md",
    "the path of the plugin is cut, the root hidden"
  )
  lacks(boom.message, "/home/me", "no path of this machine")

  local nan = refused("nan", nil, "internal", "a value JSON cannot hold")
  has(nan.message, "$.n")
  d.MAX_DOC_BYTES = 100
  local over = refused("big", nil, "payload_too_large", "an answer over the limit")
  has(over.message, "ask for a page or an area")
  d.MAX_DOC_BYTES = 8 * 1024 * 1024

  -- without the plugin's patterns the same text is internal
  local plain = new_api(new_doc(), { patterns = false })
  local pe = vim.json.decode((plain.call("list", '{"params":{"area":"nope"}}', { root = ROOT })))
  eq(pe.code, "internal", "no patterns: not recognised")

  -- ── parameter types: the plugin's own, and the small built-in ones ──
  eq(call("typed", '{"params":{"n":4}}').n, 4)
  has(
    refused("typed", '{"params":{"n":3}}', "invalid_argument", "own type").message,
    "must be even"
  )
  eq(call("typed", '{"params":{"o":{"a":1},"f":1.5,"ol":[{}]}}').kind, "tasks.typed")
  eq(call("typed", '{"params":{"o":{}}}').kind, "tasks.typed", "an empty object is an object")
  has(
    refused("typed", '{"params":{"o":[1]}}', "invalid_argument", "list for object").message,
    "must be object"
  )
  has(
    refused("typed", '{"params":{"f":"1"}}', "invalid_argument", "text for number").message,
    "must be number"
  )

  -- ── the root to hide ──
  local hooked = new_api(new_doc(), {
    root_of = function(engine_opts, opts)
      return engine_opts.root or opts.given
    end,
  })
  local he = vim.json.decode((hooked.call("list", '{"params":{"area":"nope"}}', { given = ROOT })))
  has(he.message, "<vault>/nope", "root_of may look at all options of the call")
  local nr = vim.json.decode((api.call("list", '{"params":{"area":"nope"}}', {})))
  has(nr.message, ROOT, "no root known: the message is as it is")

  -- ── last resort: an error document that cannot be made ──
  local broken = new_doc()
  local real_encode = broken.encode
  broken.encode = function(document, opts)
    if document.kind == broken.ERROR_KIND then
      return nil, { code = "internal", message = "no", retryable = false }
    end
    return real_encode(document, opts)
  end
  local last = new_api(broken)
  local lt, lc = last.call("frobnicate", nil, { root = ROOT })
  eq(
    lt,
    '{"code":"internal","kind":"tasks.error","message":"cannot encode the error","plugin":"tasks.nvim","retryable":false,"schema":1}',
    "the smallest valid document, the bytes the clients know"
  )
  eq(lc, "not_found", "the code is still the real one")
  eq(
    api.minimal_error("internal", "the host failed on this request"),
    '{"code":"internal","kind":"tasks.error","message":"the host failed on this request","plugin":"tasks.nvim","retryable":false,"schema":1}',
    "the same bytes for the host"
  )
  eq(
    new_api(doc.new({ plugin = "rules.nvim", schema = 2 })).minimal_error("io", "m"),
    '{"code":"io","kind":"rules.error","message":"m","plugin":"rules.nvim","retryable":false,"schema":2}',
    "named after the plugin"
  )

  -- ── a second plugin does not share anything ──
  local rules_doc = doc.new({ plugin = "rules.nvim", schema = 3, scope_key = "source" })
  local rules = capi.make({
    doc = rules_doc,
    methods = {
      hello = {
        params = {},
        run = function(_, opts)
          return rules_doc.head("rules.hello", opts.root)
        end,
      },
    },
  })
  local rh = vim.json.decode((rules.call("hello", nil, { root = "/x/wkdbook-Lua" })))
  eq({ rh.plugin, rh.schema, rh.source.id }, { "rules.nvim", 3, "wkdbook-Lua" })
  local re = vim.json.decode((rules.call("hello", '{"schema":4}', { root = "/x/wkdbook-Lua" })))
  eq({ re.kind, re.code }, { "rules.error", "unsupported_schema" })
  has(re.message, "speaks 3")
  eq(rules.call("list"):find("unknown method", 1, true) ~= nil, true)
  eq(rules.methods(), { "hello" })

  -- ── make: a wrong config is refused where it is made, with the position of the caller ──
  local function refused_make(cfg, part)
    local good, err = pcall(capi.make, cfg)
    ok(not good, "expected make to refuse " .. vim.inspect(cfg))
    has(tostring(err), part)
  end
  refused_make(nil, "needs a table")
  refused_make({ methods = {} }, "doc must be")
  refused_make({ doc = {}, methods = {} }, "doc must be")
  refused_make({ doc = d }, "methods must be a table")
  refused_make({ doc = d, methods = { x = {} } }, "method 'x' needs params and run")
  refused_make({ doc = d, methods = { x = { params = {} } } }, "method 'x' needs params and run")
  refused_make(
    { doc = d, methods = { x = { params = { a = "strng" }, run = function() end } } },
    "unknown type 'strng'"
  )
  refused_make({
    doc = d,
    methods = { x = { params = { a = "string" }, required = { "b" }, run = function() end } },
  }, "requires 'b'")
  ok(
    pcall(capi.make, { doc = d, methods = {} }),
    "no methods at all is a valid, if useless, contract"
  )
end
