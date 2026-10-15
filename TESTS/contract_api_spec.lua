-- TESTS/contract_api_spec.lua -- lib.nvim.contract.api: the one door of a machine contract, never a throw.

return function(H)
  local ok = H.ok
  local doc = require("lib.nvim.contract.doc")
  local capi = require("lib.nvim.contract.api")
  local json = require("lib.nvim.json.canonical")
  local with_lock = require("lib.nvim.fs.with_lock")

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
  eq(call("list", '{"schema":1.0}').kind, "tasks.list", "1.0 is the whole number 1")
  -- a schema that is no whole number is refused, not read as another one (`%d` printed 1.5 as 1 and infinity as the
  -- smallest integer, and NaN passed both comparisons)
  for _, bad in ipairs({ "1.5", "2.5", "0.5", "NaN", "Infinity", "-Infinity", "1e999", "-1e999" }) do
    local e = refused("list", '{"schema":' .. bad .. "}", "invalid_argument", "schema " .. bad)
    eq(e.message, "schema must be a whole number", "schema " .. bad)
  end
  local nan_schema = call("list", { schema = 0 / 0 })
  eq(nan_schema.code, "invalid_argument", "a request that is already a table: NaN is no schema")
  local huge_schema =
    refused("list", '{"schema":1e300}', "unsupported_schema", "a huge whole schema")
  eq(
    huge_schema.message,
    "the request asks for schema 1e+300, this engine speaks 1: update the engine",
    "named as it is, not as the smallest integer"
  )
  do
    local two = capi.make({
      doc = doc.new({ plugin = "tasks.nvim", schema = 2 }),
      methods = {
        m = {
          params = {},
          run = function()
            return { kind = "tasks.m" }
          end,
        },
      },
    })
    for _, bad in ipairs({ "1.5", "NaN", "2.5", "Infinity" }) do
      local code_ = select(2, two.call("m", '{"schema":' .. bad .. "}"))
      eq(code_, "invalid_argument", "an engine of schema 2 does not accept schema " .. bad)
    end
    eq(select(2, two.call("m", '{"schema":2}')), nil, "its own schema")
    eq(select(2, two.call("m", '{"schema":1}')), nil, "and an older one")
    eq(select(2, two.call("m", '{"schema":3}')), "unsupported_schema")
  end

  -- the schema is checked before the fields: a client of a newer schema that sends a field (or, for a flat method, a
  -- parameter) this engine does not know is told to update, not that its request is malformed
  eq(
    refused(
      "list",
      '{"schema":2,"extra":1}',
      "unsupported_schema",
      "skew wins over a request field"
    ).code,
    "unsupported_schema"
  )
  has(
    refused(
      "ops",
      '{"schema":2,"newparam":1}',
      "unsupported_schema",
      "a new parameter of a flat method"
    ).message,
    "update the engine"
  )
  refused("ops", '{"schema":2,"extra":1,"dry_run":"yes"}', "unsupported_schema", "and a wrong type")
  has(
    refused("list", '{"schema":0,"extra":1}', "invalid_argument", "a bad schema and a field").message,
    "schema must be 1 or more"
  )
  has(
    refused("list", '{"schema":"x","extra":1}', "invalid_argument", "a schema that is text").message,
    "schema must be a number"
  )
  has(
    refused("list", '{"schema":null,"extra":1}', "invalid_argument", "a null schema is absent").message,
    "unknown field 'extra'"
  )
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
  -- a number the canonical JSON cannot write (infinity, a whole number of 2^53 or more) is a bad parameter, not an
  -- `internal` error when the method echoes it into its answer
  for _, bad in ipairs({
    "1e999",
    "-1e999",
    "Infinity",
    "-Infinity",
    "NaN",
    "1e300",
    "9007199254740993",
    "9007199254740992",
    "1152921504606846976",
  }) do
    local e =
      refused("list", '{"params":{"offset":' .. bad .. "}}", "invalid_argument", "offset " .. bad)
    eq(e.message, "parameter 'offset' must be integer", "offset " .. bad)
  end
  eq(
    call("list", '{"params":{"offset":9007199254740991}}').params.offset,
    9007199254740991,
    "the largest whole number the JSON holds is a valid integer"
  )
  eq(call("list", '{"params":{"offset":-9007199254740991}}').params.offset, -9007199254740991)
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

  -- ── several faults in one request: the same one is told in every process ──
  -- (`pairs` visits string keys in an order that differs from process to process, so the answer used to depend on
  -- which Neovim ran; with so many candidates the old code failed these rows in all but a few runs)
  has(
    refused("list", '{"params":{"offset":"y","limit":"x"}}', "invalid_argument", "two wrong types").message,
    "parameter 'limit' must be integer",
    "the alphabetically first wrong parameter"
  )
  eq(
    refused("list", '{"params":{"d4":1,"c3":1,"b2":1,"a1":1}}', "invalid_argument", "four unknown").message,
    "list takes no parameter 'a1' (parameters: area, limit, offset, status)"
  )
  eq(
    refused("list", '{"zz":1,"yy":2,"xx":3,"ww":4,"params":{}}', "invalid_argument", "four fields").message,
    "unknown field 'ww' in the request (fields: schema, params)"
  )
  do
    local letters, request = {}, {}
    for i = 1, 26 do
      local letter = string.char(122 - i + 1) -- z .. a
      letters[#letters + 1] = ('"%s":1'):format(letter .. letter)
      request[#request + 1] = letter
    end
    local fields = '{"params":{},' .. table.concat(letters, ",") .. "}"
    eq(
      refused("list", fields, "invalid_argument", "26 unknown fields").message,
      "unknown field 'aa' in the request (fields: schema, params)"
    )
    local flat_fields =
      refused("ops", fields, "invalid_argument", "26 unknown fields of a flat method")
    has(flat_fields.message, "unknown field 'aa' in the request (fields: schema, client_op_id")
    local wide = { params = {}, flat = false }
    local names = {}
    for _, letter in ipairs(request) do
      wide.params[letter .. "_n"] = "integer"
      names[#names + 1] = ('"%s_n":"x"'):format(letter)
    end
    wide.run = function()
      return { kind = "tasks.wide" }
    end
    local wide_api = capi.make({ doc = d, methods = { wide = wide } })
    local wrong = vim.json.decode(
      (wide_api.call("wide", '{"params":{' .. table.concat(names, ",") .. "}}", { root = ROOT }))
    )
    eq(wrong.message, "parameter 'a_n' must be integer", "26 wrong types: the first by name")
    local unknown_params = {}
    for _, letter in ipairs(request) do
      unknown_params[#unknown_params + 1] = ('"%s_x":1'):format(letter)
    end
    local unknown_param = vim.json.decode(
      (
        wide_api.call(
          "wide",
          '{"params":{' .. table.concat(unknown_params, ",") .. "}}",
          { root = ROOT }
        )
      )
    )
    has(unknown_param.message, "wide takes no parameter 'a_x' (parameters: a_n, b_n,")
  end
  -- a request that is already a Lua table may have keys that are no text: no throw, and the order is by their text
  local table_keys = call("list", { [1] = "a", x = 1 })
  eq(table_keys.code, "invalid_argument", "a table with a key that is no text")
  has(
    table_keys.message,
    "unknown field '1' in the request",
    "named by its text, first in byte order"
  )
  eq(
    call("list", { [2.5] = 1, [true] = 2 }).message,
    "unknown field '2.5' in the request (fields: schema, params)"
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
  eq(#'{"params":{"a":"0"}}', 20, "(the next two requests are 20 and 21 bytes)")
  eq(select(2, tight.call("m", '{"params":{"a":"0"}}')), nil, "exactly at the limit is fine")
  eq(
    select(2, tight.call("m", '{"params":{"a":"01"}}')),
    "payload_too_large",
    "one byte over is refused"
  )
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

  -- an error that is no text: the same bytes on every call, no address of this process, and still a document
  local bad_to_string = setmetatable({}, {
    __tostring = function()
      error("no")
    end,
  })
  local odd = capi.make({
    doc = d,
    methods = {
      raise_coded = {
        params = {},
        run = function()
          error({ code = "conflict" })
        end,
      },
      raise_message = {
        params = {},
        run = function()
          error({ message = "x" })
        end,
      },
      return_message = {
        params = {},
        run = function()
          return nil, { message = "x" }
        end,
      },
      return_table = {
        params = {},
        run = function()
          return nil, {}
        end,
      },
      raise_hostile = {
        params = {},
        run = function()
          error(bad_to_string)
        end,
      },
      return_hostile = {
        params = {},
        run = function()
          return nil, bad_to_string
        end,
      },
    },
  })
  local expected_text = {
    raise_coded = "error value of type table",
    raise_message = "x",
    return_message = "x",
    return_table = "error value of type table",
    raise_hostile = "error value of type table",
    return_hostile = "error value of type table",
  }
  for name, message in pairs(expected_text) do
    local called, first, first_code = pcall(odd.call, name, nil, { root = ROOT })
    ok(called, name .. ": the door does not raise: " .. tostring(first))
    local again = odd.call(name, nil, { root = ROOT })
    ok(first == again, name .. ": the same request gives the same bytes")
    lacks(first, "0x", name .. ": no address of this process")
    lacks(first, "table:", name .. ": no 'table: 0x...'")
    eq(first_code, "internal", name)
    eq(vim.json.decode(first).message, message, name)
  end

  -- a hand-built error table that lacks what the type asks for is still an error document, not a throw out of the
  -- door (a `nil, { code = "not_found" }` used to fail in the redaction of the missing message)
  local malformed = capi.make({
    doc = d,
    methods = {
      no_message = {
        params = {},
        run = function()
          return nil, { code = "not_found" }
        end,
      },
      number_message = {
        params = {},
        run = function()
          return nil, { code = "io", message = 5 }
        end,
      },
      text_details = {
        params = {},
        run = function()
          return nil, { code = "io", message = "m", details = "x" }
        end,
      },
      number_code = {
        params = {},
        run = function()
          return nil, { code = 5, message = "m" }
        end,
      },
    },
  })
  local expected_error = {
    no_message = { "not_found", "not_found" },
    number_message = { "io", "5" },
    text_details = { "io", "m" },
    number_code = { "internal", "m" },
  }
  for name, want in pairs(expected_error) do
    for _, with_root in ipairs({ true, false }) do
      local label = name .. (with_root and " with a root" or " without one")
      local called, text_, code_ =
        pcall(malformed.call, name, nil, { root = with_root and ROOT or nil })
      ok(called, label .. ": the door does not raise: " .. tostring(text_))
      local e = vim.json.decode(text_)
      eq({ e.kind, e.code, e.message, code_ }, { "tasks.error", want[1], want[2], want[1] }, label)
      eq(e.details, nil, label .. ": details that is no table is left out")
    end
  end

  -- a doc that raises while it makes the error document: the last resort answers, the door still does not raise
  local raising = new_doc()
  raising.error_doc = function()
    error("boom")
  end
  local rt, rc = new_api(raising).call("frobnicate", nil, { root = ROOT })
  eq(
    rt,
    '{"code":"internal","kind":"tasks.error","message":"cannot encode the error","plugin":"tasks.nvim","retryable":false,"schema":1}',
    "the smallest valid document"
  )
  eq(rc, "not_found", "the code is still the real one")
  local numeric_root = new_api(new_doc(), {
    root_of = function()
      return 5
    end,
  })
  eq(
    select(2, numeric_root.call("frobnicate", nil, { root = ROOT })),
    "not_found",
    "a root_of that answers no text does not make the door raise"
  )

  -- ── a hook of the plugin that raises: the door answers `internal`, it does not raise ──
  local fragile = capi.make({
    doc = d,
    types = {
      path = function(value)
        return value:match("^/") ~= nil -- raises on a number
      end,
      leaky = function()
        error("no such place " .. ROOT .. "/x", 0)
      end,
    },
    methods = {
      m = {
        params = { s = "path" },
        run = function()
          return { kind = "tasks.m" }
        end,
      },
      leak = {
        params = { s = "leaky" },
        run = function()
          return { kind = "tasks.leak" }
        end,
      },
    },
  })
  local function internal_document(label, text_, code_, expected_message)
    local e = vim.json.decode(text_)
    eq({ e.kind, e.code, code_ }, { d.ERROR_KIND, "internal", "internal" }, label)
    eq(e.plugin, "tasks.nvim", label)
    eq(e.schema, 1, label)
    eq(e.retryable, false, label)
    lacks(text_, ROOT, label .. ": no path of this machine")
    if expected_message then
      has(e.message, expected_message, label)
    end
    return e
  end
  do
    local raised, answer_text, c = pcall(fragile.call, "m", '{"params":{"s":5}}', { root = ROOT })
    ok(
      raised,
      "a type function that raises on a number does not make the door raise: "
        .. tostring(answer_text)
    )
    internal_document("type function", answer_text, c)
    eq(vim.json.decode(answer_text).vault.id, "vault", "a full document: the head is there")
    eq(
      select(2, fragile.call("m", '{"params":{"s":"/ok"}}', { root = ROOT })),
      nil,
      "and a text is fine"
    )
    raised, answer_text, c = pcall(fragile.call, "leak", '{"params":{"s":"x"}}', { root = ROOT })
    ok(raised, "the message of the raise is hidden like any other")
    local e = internal_document("leaky type function", answer_text, c, "<vault>/x")
    eq(e.message, "no such place <vault>/x")
  end

  -- a root_of that raises: not even the root is known, the smallest valid document
  local no_root = new_api(new_doc(), {
    root_of = function()
      error("no vault here")
    end,
  })
  do
    local raised, answer_text, c = pcall(no_root.call, "hello", nil, { root = ROOT })
    ok(raised, "a root_of that raises does not make the door raise: " .. tostring(answer_text))
    internal_document("root_of", answer_text, c, "no vault here")
    raised, answer_text, c = pcall(no_root.call, "frobnicate", nil, { root = ROOT })
    ok(raised, "also on the error path")
    internal_document("root_of on an error", answer_text, c)
  end
  -- the smallest document has nothing to hide a root with, so its message is scrubbed of the install path
  do
    local leaky_root = new_api(new_doc(), {
      root_of = function()
        error("/opt/x/lua/m/a.lua:3: boom", 0)
      end,
    })
    local raised, answer_text, c = pcall(leaky_root.call, "hello", nil, { root = ROOT })
    ok(raised, "a root_of that raises with a path: " .. tostring(answer_text))
    local e = internal_document("root_of with a path", answer_text, c)
    eq(e.message, "m/a.lua:3: boom", "no install path of this machine")
  end

  -- an opts that is no table, a method name that cannot be printed
  for _, bad_opts in ipairs({ 5, true, "x" }) do
    local raised, answer_text, c = pcall(api.call, "hello", nil, bad_opts)
    ok(
      raised,
      "opts " .. vim.inspect(bad_opts) .. " does not make the door raise: " .. tostring(answer_text)
    )
    if raised and type(bad_opts) ~= "string" then
      internal_document("opts " .. vim.inspect(bad_opts), answer_text, c)
    end
  end
  do
    local unprintable = setmetatable({}, {
      __tostring = function()
        error("no name")
      end,
    })
    local raised, answer_text, c = pcall(api.call, unprintable, nil, { root = ROOT })
    ok(
      raised,
      "a method name whose __tostring raises does not make the door raise: "
        .. tostring(answer_text)
    )
    internal_document("method name", answer_text, c)
  end
  -- a root that is no text on an error path (it used to raise out of `vim.fs.basename`)
  for _, bad_root in ipairs({ {}, 42, true }) do
    local raised, answer_text, c = pcall(api.call, "frobnicate", nil, { root = bad_root })
    ok(
      raised,
      "root " .. vim.inspect(bad_root) .. " does not make the door raise: " .. tostring(answer_text)
    )
    eq(vim.json.decode(answer_text).kind, d.ERROR_KIND)
    eq(c, "not_found", "the code is still the real one")
  end

  -- ── what run hands on besides the error: `info`, the third value (fs.with_lock gives it) ──
  local with_info = capi.make({
    doc = d,
    methods = {
      conflict = {
        params = {},
        run = function()
          return nil,
            "file changed",
            { code = "conflict", expected = "a", actual = "b", secret = "s" }
        end,
      },
      locked = {
        params = {},
        run = function()
          return nil, "x", { code = "locked" }
        end,
      },
      stuck = {
        params = {},
        run = function()
          return nil, "something", { code = "forbidden", retryable = true }
        end,
      },
      flag = {
        params = {},
        run = function()
          return nil, "no such thing", true
        end,
      },
      count = {
        params = {},
        run = function()
          return nil, "cannot read x", 5
        end,
      },
      word = {
        params = {},
        run = function()
          return nil, "x", "forbidden"
        end,
      },
      table_wins = {
        params = {},
        run = function()
          return nil, { code = "io", message = "m" }, { code = "conflict" }
        end,
      },
      no_code = {
        params = {},
        run = function()
          return nil, "unknown area 'q'", { id = "a" }
        end,
      },
      plain = {
        params = {},
        run = function()
          return nil, "cannot read x"
        end,
      },
      forwards_lock = {
        params = {},
        run = function()
          -- a method that simply hands on what the lock gives: the answer of its function, three values
          return with_lock(vim.fn.tempname(), function()
            return nil, "file changed", { code = "conflict", expected = "a", actual = "b" }
          end)
        end,
      },
    },
    patterns = { { code = "not_found", find = { "unknown area" } } },
  })
  local function info_call(name)
    local raised, answer_text, c = pcall(with_info.call, name, nil, { root = ROOT })
    ok(raised, name .. ": the door does not raise: " .. tostring(answer_text))
    return vim.json.decode(answer_text), c
  end
  local ie, ic = info_call("conflict")
  eq(
    { ie.code, ic, ie.message, ie.retryable, ie.details },
    { "conflict", "conflict", "file changed", false, { expected = "a", actual = "b" } },
    "the code and the details come from the source; only the known keys are shown"
  )
  ie = info_call("locked")
  eq({ ie.code, ie.retryable, ie.details }, { "locked", true, nil }, "locked is retryable")
  ie = info_call("stuck")
  eq({ ie.code, ie.retryable }, { "forbidden", true }, "retryable from the source")
  -- a third value that is no table is no info (and `classify` would raise on it): the text decides
  for name, want in pairs({ flag = "not_found", count = "io", word = "internal" }) do
    ie, ic = info_call(name)
    eq({ ie.code, ic }, { want, want }, name)
    eq(ie.details, nil, name .. ": a third value that is no table is ignored")
  end
  ie = info_call("table_wins")
  eq({ ie.code, ie.message }, { "io", "m" }, "an error table as the second value wins over info")
  ie = info_call("no_code")
  eq(ie.code, "not_found", "info without a code is no info: the patterns of the plugin")
  ie = info_call("plain")
  eq(ie.code, "io", "no third value: the built-in patterns")
  ie = info_call("forwards_lock")
  eq(
    { ie.code, ie.message, ie.details },
    { "conflict", "file changed", { expected = "a", actual = "b" } },
    "what fs.with_lock hands back goes through as it is"
  )

  -- ── a request echoes its own names into the message: the work follows its length, not the hits of the root ──
  -- (the redaction was quadratic in the number of occurrences: 238 KB of root took seconds)
  do
    local root = "E:/Users/me/vault"
    local key = root:rep(14000)
    local request = vim.json.encode({ [key] = 1 })
    local started = vim.uv.hrtime()
    local text_, code_ = api.call("hello", request, { root = root })
    local took_ms = (vim.uv.hrtime() - started) / 1e6
    local e = vim.json.decode(text_)
    eq(code_, "invalid_argument", "an unknown field")
    eq(e.message:find("unknown field '", 1, true), 1)
    lacks(e.message, root, "the root is hidden in every copy")
    ok(select(2, e.message:gsub("<vault>", "")) >= 1, "the copies that are echoed are replaced")
    ok(#e.message < 300, "the echoed name is clipped, not 238 KB: " .. #e.message)
    ok(took_ms < 500, ("a field made of the root 14000 times took %.0f ms"):format(took_ms))
    started = vim.uv.hrtime()
    text_, code_ = api.call(root:rep(14000), "{}", { root = root })
    took_ms = (vim.uv.hrtime() - started) / 1e6
    eq(code_, "not_found", "an unknown method")
    lacks(text_, root)
    ok(took_ms < 500, ("a method made of the root 14000 times took %.0f ms"):format(took_ms))
    started = vim.uv.hrtime()
    text_, code_ = api.call("list", vim.json.encode({ params = { [key] = 1 } }), { root = root })
    took_ms = (vim.uv.hrtime() - started) / 1e6
    eq(code_, "invalid_argument", "an unknown parameter")
    lacks(text_, root)
    ok(took_ms < 500, ("a parameter made of the root 14000 times took %.0f ms"):format(took_ms))
  end

  -- ── the names of a request are echoed clipped and printable (the client's text, shown on a terminal) ──
  do
    local esc = string.char(27)
    local bell = string.char(7)
    local long = ("n"):rep(500)
    local cases = {
      {
        "unknown method",
        function(name)
          return api.call(name, "{}", { root = ROOT })
        end,
        "not_found",
      },
      {
        "unknown field",
        function(name)
          return api.call("list", vim.json.encode({ [name] = 1 }), { root = ROOT })
        end,
        "invalid_argument",
      },
      {
        "unknown parameter",
        function(name)
          return api.call("list", vim.json.encode({ params = { [name] = 1 } }), { root = ROOT })
        end,
        "invalid_argument",
      },
    }
    for _, c in ipairs(cases) do
      local c1 = string.char(194, 155) -- U+009B, a CSI to an 8-bit terminal
      local text_, code_ = c[2](esc .. "[31mred" .. bell .. c1 .. "x")
      eq(code_, c[3], c[1])
      local m = vim.json.decode(text_).message
      ok(
        not m:find(esc, 1, true) and not m:find(bell, 1, true),
        c[1] .. ": no raw control character in the message"
      )
      ok(not m:find(c1, 1, true), c[1] .. ": no raw C1 character")
      has(m, string.char(92) .. "x1b", c[1] .. ": the escape is written out")
      has(m, string.char(92) .. "u009b", c[1] .. ": and the C1 character too")
      text_ = c[2](long)
      m = vim.json.decode(text_).message
      ok(#m < 400, c[1] .. ": a 500-character name is clipped: " .. #m)
      ok(not m:find(long, 1, true), c[1] .. ": and not echoed whole")
    end
  end

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
  ok(pcall(capi.make, { doc = d, methods = {}, patterns = nil }), "nil patterns build an api")
  ok(pcall(capi.make, { doc = d, methods = {}, patterns = {} }), "an empty list builds an api")

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
  for _, bad in ipairs({
    "1e999",
    "-1e999",
    "Infinity",
    "-Infinity",
    "NaN",
    "1e16",
    "-1e16",
    "9007199254740992",
  }) do
    local e = refused("typed", '{"params":{"f":' .. bad .. "}}", "invalid_argument", "f " .. bad)
    eq(e.message, "parameter 'f' must be number", "f " .. bad)
  end
  for _, fine in ipairs({ "1.5", "-9007199254740991", "9007199254740991", "0", "-0.25", "1e15" }) do
    eq(call("typed", '{"params":{"f":' .. fine .. "}}").kind, "tasks.typed", "f " .. fine)
  end

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
  -- the default root_of hands the root over as given, and a root from the environment or the working directory is
  -- not tidy: the message (forward slashes, from the engine) must still be hidden, and the source still named
  for _, untidy in ipairs({
    [[C:\Users\me\vault]],
    [[C:\Users\me/vault]],
    "C:/Users/me/vault/",
    "C:/Users/me/vault//",
    [[C:\Users\me\vault\]],
  }) do
    local ue = call("list", '{"params":{"area":"nope"}}', { root = untidy })
    has(ue.message, "unknown area 'nope' in <vault>/nope", "root " .. untidy)
    lacks(ue.message, "Users", "no path of this machine, root " .. untidy)
    eq(ue.vault.id, "vault", "the source keeps its name, root " .. untidy)
  end
  -- an untidy root also hides the root inside the message of a raised error
  local ub = call("boom", nil, { root = [[C:\Users\me\vault]] })
  has(ub.message, "boom at <vault>/a.md", "a raise: the root is hidden")
  lacks(ub.message, "Users", "a raise: no path of this machine")

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
    -- through a function of this file and not `pcall(capi.make, cfg)`: a message has a position only when something
    -- of Lua is the caller (and no tail call, which would hide it), and the position must be the caller's
    local good, err = pcall(function()
      capi.make(cfg)
    end)
    ok(not good, "expected make to refuse " .. vim.inspect(cfg))
    has(tostring(err), part)
    has(tostring(err), "contract_api_spec.lua:", "the position is the caller's: " .. tostring(err))
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

  -- the patterns are checked where they are handed in, not when a message falls through to a bad one
  local good_rule = { code = "not_found", find = { "unknown area" } }
  refused_make(
    { doc = d, methods = {}, patterns = { good_rule, { code = "x", find = "y" } } },
    "contract.api.make: patterns[2].find must be a list of strings"
  )
  refused_make(
    { doc = d, methods = {}, patterns = { good_rule, { find = { "y" } } } },
    "patterns[2].code must be a string"
  )
  refused_make(
    { doc = d, methods = {}, patterns = { { code = "not_found", find = "unknown" } } },
    "patterns[1].find must be a list of strings"
  )
  refused_make({ doc = d, methods = {}, patterns = { false } }, "patterns[1] must be a table")
  refused_make({ doc = d, methods = {}, patterns = "oops" }, "patterns must be a list")
  local _, at = pcall(function()
    local made = capi.make({ doc = d, methods = {}, patterns = { {} } }) -- no tail call: it would hide the caller
    return made
  end)
  ok(
    tostring(at):find("contract_api_spec.lua", 1, true),
    "the position is the caller's: " .. tostring(at)
  )
  ok(
    pcall(capi.make, { doc = d, methods = {}, patterns = false }),
    "false still means no patterns of my own"
  )
end
