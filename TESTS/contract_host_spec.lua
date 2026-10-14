-- TESTS/contract_host_spec.lua -- lib.nvim.contract.host: the persistent engine over a line protocol, in process and
-- as a real child Neovim started from templates/contract_host.lua.
--
-- The rule it holds: a question through the host gets the document `api.call` gives, byte for byte.

return function(H)
  local ok = H.ok
  local doc = require("lib.nvim.contract.doc")
  local capi = require("lib.nvim.contract.api")
  local chost = require("lib.nvim.contract.host")
  local uv = vim.uv or vim.loop

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local function has(text, part, msg)
    ok(type(text) == "string" and text:find(part, 1, true), msg or ("expected " .. part))
  end

  local ROOT = "C:/Users/me/vault"

  local d = doc.new({ plugin = "tasks.nvim", schema = 1 })
  d.clock = function()
    return "2026-01-01T00:00:00Z"
  end
  d.engine_info = function()
    return { version = "0.1.0", git = "abc1234", nvim = "v0.11.0" }
  end

  local last_opts
  local api = capi.make({
    doc = d,
    methods = {
      hello = {
        params = {},
        run = function(_, opts)
          last_opts = opts
          return d.head(d.kind("hello"), opts.root)
        end,
      },
      echo = {
        params = { text = "string" },
        run = function(p)
          return { kind = "tasks.echo", text = p.text }
        end,
      },
      flatty = {
        flat = true,
        keep_null = true,
        params = { a = "integer", b = "string" },
        run = function(p)
          return { kind = "tasks.flat", a = p.a, b = p.b }
        end,
      },
    },
  })

  -- ── make: a wrong config is refused where it is made, with the position of the caller ──
  local function refused_make(cfg, part, label)
    local good, err = pcall(chost.make, cfg)
    ok(not good, "expected make to refuse " .. (label or vim.inspect(cfg)))
    has(tostring(err), part)
  end
  refused_make(nil, "needs a table")
  refused_make({}, "api must be")
  refused_make({ api = {} }, "api must be")
  refused_make({ api = { call = function() end } }, "api must be")
  refused_make(
    { api = { call = function() end, METHODS = {} } },
    "api must be",
    "an api without minimal_error"
  )
  refused_make({ api = api, protocol = 0 }, "protocol must be")
  refused_make({ api = api, protocol = 1.5 }, "protocol must be")
  refused_make({ api = api, protocol = "1" }, "protocol must be")
  refused_make({ api = api, call_opts = 5 }, "call_opts must be")

  local host = chost.make({ api = api, call_opts = { root = ROOT } })
  eq(host.PROTOCOL, 1)
  eq(chost.make({ api = api, protocol = 3 }).PROTOCOL, 3)
  eq(host.max_line_bytes(), 256 * 1024 + 256, "a request plus the id and the method")

  -- ── handle: one line in, one line out, the bytes of api.call ──
  for _, case in ipairs({
    { id = "1", method = "hello", params = "" },
    { id = "2", method = "echo", params = '{"text":"hi"}' },
    { id = "3", method = "echo", params = '{"text":"ü日本"}' },
  }) do
    local want = api.call(
      case.method,
      case.params ~= "" and ('{"params":' .. case.params .. "}") or nil,
      { root = ROOT }
    )
    local reply = host.handle(case.id .. "\t" .. case.method .. "\t" .. case.params)
    eq(reply, case.id .. "\t" .. want, case.method .. ": same bytes as api.call")
    ok(not reply:sub(#case.id + 2):find("\n"), case.method .. ": one line")
  end
  eq(last_opts, { root = ROOT }, "the options of the plugin reach the call")

  -- a flat method carries its fields at the top of the request, as on the command line
  local flat = '{"a":1,"b":"x"}'
  eq(host.handle("7\tflatty\t" .. flat), "7\t" .. api.call("flatty", flat, { root = ROOT }))
  eq(vim.json.decode(host.handle("7\tflatty\t" .. flat):sub(3)).a, 1)

  -- a method without a tab after it, and without params
  eq(host.handle("4\thello"), "4\t" .. api.call("hello", nil, { root = ROOT }), "no second tab")

  -- a request the dispatcher refuses is its own error document, with the id of the question
  local refused = host.handle("8\tbogus\t")
  ok(refused ~= nil and refused:sub(1, 2) == "8\t", "an unknown method is answered with its id")
  eq(vim.json.decode(refused:sub(3)).code, "not_found")
  eq(vim.json.decode(host.handle("9\techo\t{not json"):sub(3)).code, "invalid_argument")
  -- (documented) the params text is spliced into the request, not parsed: it can carry a top-level field of its own.
  -- That is the same client that writes the whole line, so it is no way to anything it could not ask for anyway.
  eq(
    vim.json.decode(host.handle('9\techo\t1,"schema":9'):sub(3)).code,
    "unsupported_schema",
    "the spliced field is judged by the dispatcher like any other"
  )
  eq(
    vim.json.decode(host.handle('9\techo\t{"text":"x"},"extra":1'):sub(3)).code,
    "invalid_argument",
    "and an unknown one is refused"
  )

  -- a Windows line ending is not part of the request
  eq(host.handle("10\thello\t\r"), "10\t" .. api.call("hello", nil, { root = ROOT }))
  eq(host.handle("10\thello\r"), "10\t" .. api.call("hello", nil, { root = ROOT }))

  -- what is no request is skipped (nil), never answered with a guess
  eq(host.handle("hello"), nil)
  eq(host.handle(""), nil)
  eq(host.handle("x\thello\t"), nil)
  eq(host.handle("1234567890123456\thello\t"), nil, "an id of 16 digits")
  eq(host.handle("123456789012345\thello\t") ~= nil, true, "15 digits are fine")
  eq(host.handle("1\t\t"), nil, "no method")
  eq(
    vim.json.decode(host.handle("1\tbad-name\t"):sub(3)).code,
    "not_found",
    "a method name ends at the dash: 'bad' is asked for, and the dispatcher refuses it"
  )
  eq(host.handle(5), nil, "not even a text")
  eq(host.handle(nil), nil)

  -- call_opts: a function is asked per request
  local asked = 0
  local per_request = chost.make({
    api = api,
    call_opts = function()
      asked = asked + 1
      return { root = "/r" .. asked }
    end,
  })
  per_request.handle("1\thello\t")
  per_request.handle("2\thello\t")
  eq(last_opts, { root = "/r2" })
  eq(asked, 2)
  chost.make({ api = api, call_opts = function() end }).handle("1\thello\t")
  eq(last_opts, {}, "a function that answers nothing: no options")
  chost.make({ api = api }).handle("1\thello\t")
  eq(last_opts, {}, "no call_opts: no options")

  -- the options reach the dispatcher as a table whatever the plugin hands in
  local seen_opts = {}
  local spy_api = {
    METHODS = {},
    MAX_REQUEST_BYTES = 100,
    minimal_error = api.minimal_error,
    call = function(_, _, opts)
      seen_opts[#seen_opts + 1] = opts
      return "{}"
    end,
  }
  chost.make({ api = spy_api }).handle("1\thello\t")
  chost.make({ api = spy_api, call_opts = function() end }).handle("1\thello\t")
  chost
    .make({
      api = spy_api,
      call_opts = function()
        return "text"
      end,
    })
    .handle("1\thello\t")
  eq(seen_opts, { {}, {}, {} }, "always a table")

  -- a dispatcher that raises or answers no text is a document of its own, never a dead host
  local broken = {
    METHODS = {},
    MAX_REQUEST_BYTES = 100,
    minimal_error = api.minimal_error,
    call = function()
      error("boom")
    end,
  }
  local fallback = chost.make({ api = broken }).handle("5\thello\t")
  eq(fallback:sub(1, 2), "5\t")
  eq(vim.json.decode(fallback:sub(3)).message, "the host failed on this request")
  broken.call = function()
    return nil
  end
  eq(
    chost.make({ api = broken }).handle("6\thello\t"):sub(1, 2),
    "6\t",
    "no text from the dispatcher"
  )
  broken.call = function()
    return "a\nb\r\nc"
  end
  eq(chost.make({ api = broken }).handle("6\thello\t"), "6\ta b  c", "a line break is whitespace")

  -- ── serve: in process, with streams that are tables ──
  ---@param lines string[]
  ---@param opts? { fail_after?: integer }
  local function streams(lines, opts)
    opts = opts or {}
    local input = { pos = 0, lines = lines }
    function input:read(fmt)
      assert(fmt == "l", "the host reads lines")
      self.pos = self.pos + 1
      return self.lines[self.pos]
    end
    local output = { out = {}, flushed = 0 }
    function output:write(text)
      if opts.fail_after and #self.out >= opts.fail_after then
        return nil, "EPIPE"
      end
      self.out[#self.out + 1] = text
      return self
    end
    function output:flush()
      self.flushed = self.flushed + 1
    end
    return input, output
  end

  local warnings = {}
  local function warn(text)
    warnings[#warnings + 1] = text
  end

  local input, output = streams({
    "1\thello\t",
    "garbage",
    "",
    "2\techo\t" .. '{"text":"x"}',
  })
  host.serve(input, output, warn)
  eq(output.out[1], "ready\t1\n", "ready, first")
  eq(output.out[2], "1\t" .. api.call("hello", nil, { root = ROOT }) .. "\n")
  eq(output.out[3], "2\t" .. api.call("echo", '{"params":{"text":"x"}}', { root = ROOT }) .. "\n")
  eq(#output.out, 3, "nothing for a line that is no request")
  eq(
    warnings,
    { "host: a line that is not a request is skipped" },
    "told once; an empty line is not worth a word"
  )
  eq(output.flushed, 3, "flushed after every line")
  eq(input.pos, 5, "read until the input ended")

  -- the protocol number
  local _, out3 = streams({})
  chost.make({ api = api, protocol = 3 }).serve(streams({}), out3, warn)
  eq(out3.out, { "ready\t3\n" })

  -- a line that is too long: skipped, told, and when it starts with an id the client gets an answer
  warnings = {}
  local small = capi.make({
    doc = d,
    max_request_bytes = 20,
    methods = { hello = api.METHODS.hello },
  })
  local small_host = chost.make({ api = small, call_opts = { root = ROOT } })
  eq(small_host.max_line_bytes(), 20 + 256)
  local long = "5\thello\t" .. string.rep("x", 400)
  local in2, out2 = streams({ long, "6\thello\t", string.rep("y", 400) })
  small_host.serve(in2, out2, warn)
  eq(out2.out[1], "ready\t1\n")
  local answered = out2.out[2]
  eq(answered:sub(1, 2), "5\t", "the answer carries the id of the long line")
  local over = vim.json.decode(answered:sub(3))
  eq({ over.code, over.kind }, { "payload_too_large", "tasks.error" })
  has(over.message, "a request is at most 20 bytes")
  eq(out2.out[3]:sub(1, 2), "6\t", "and the next question is answered as usual")
  eq(#out2.out, 3, "a long line without an id gets no answer")
  eq(#warnings, 2)
  has(warnings[1], "a line of ")
  has(warnings[1], " bytes is skipped")
  -- the limit is read at call time
  small.MAX_REQUEST_BYTES = 1000
  eq(small_host.max_line_bytes(), 1256)

  -- an id of 16 digits on a long line gets no answer (it is no id)
  small.MAX_REQUEST_BYTES = 20
  local in4, out4 = streams({ "1234567890123456\t" .. string.rep("x", 400) })
  small_host.serve(in4, out4, warn)
  eq(#out4.out, 1, "only ready: a 16-digit id is no id")

  -- the output goes away: the host ends and does not read on
  local in5, out5 = streams({ "1\thello\t", "2\thello\t", "3\thello\t" }, { fail_after = 2 })
  host.serve(in5, out5, warn)
  eq(#out5.out, 2, "ready and the first answer, then the write failed")
  eq(in5.pos, 2, "the host stopped reading when it could not answer")
  local in6, out6 = streams({ "1\thello\t" }, { fail_after = 0 })
  host.serve(in6, out6, warn)
  eq(in6.pos, 0, "not even ready could be written: nothing is read")

  -- the default warn goes to stderr
  local captured = {}
  local in7, out7 = streams({ "garbage" })
  H.with_patched(io, "stderr", {
    write = function(_, text)
      captured[#captured + 1] = text
    end,
  }, function()
    host.serve(in7, out7)
  end)
  eq(captured, { "host: a line that is not a request is skipped\n" })

  -- ── a real child Neovim, started from the template ──
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/plugin/lua/spec_host_plugin", "p")
  vim.fn.mkdir(dir .. "/plugin/scripts", "p")
  local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
  end

  write(
    dir .. "/plugin/lua/spec_host_plugin/host.lua",
    [=[
local doc = require("lib.nvim.contract.doc")
local capi = require("lib.nvim.contract.api")
local d = doc.new({ plugin = "spec.nvim", schema = 1 })
d.clock = function()
  return "2026-01-01T00:00:00Z"
end
local api = capi.make({
  doc = d,
  methods = {
    hello = {
      params = {},
      run = function(_, opts)
        return d.head(d.kind("hello"), opts.root)
      end,
    },
    echo = {
      params = { text = "string" },
      run = function(p)
        return { kind = "spec.echo", text = p.text, pid = vim.uv.os_getpid() }
      end,
    },
  },
})
return require("lib.nvim.contract.host").make({
  api = api,
  call_opts = function()
    return { root = vim.env.SPEC_ROOT }
  end,
})
]=]
  )

  local template =
    assert(io.open(vim.fn.getcwd() .. "/templates/contract_host.lua", "rb"):read("*a"))
  local script_text = template
    :gsub('local MODULE = "your_plugin.host"', 'local MODULE = "spec_host_plugin.host"')
    :gsub('local PLUGIN = "your%-plugin.nvim"', 'local PLUGIN = "spec.nvim"')
  ok(
    script_text:find("spec_host_plugin.host", 1, true),
    "the template names its module in the place the spec replaces"
  )
  write(dir .. "/plugin/scripts/spec-host.lua", script_text)
  local script = dir .. "/plugin/scripts/spec-host.lua"

  local lib_dir = vim.fn.getcwd()
  ok(
    vim.fn.isdirectory(lib_dir .. "/lua/lib/nvim") == 1,
    "the spec runs from the lib.nvim checkout"
  )

  ---@param stdin string
  ---@param env table
  local function run_child(stdin, env)
    local base = { NVIM = vim.NIL, NVIM_LISTEN_ADDRESS = vim.NIL }
    return vim
      .system(
        { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", script },
        { text = true, stdin = stdin, env = vim.tbl_extend("force", base, env) }
      )
      :wait(60000)
  end

  local child = run_child(
    table.concat(
      { "1\thello\t", '2\techo\t{"text":"x"}', "garbage", '3\techo\t{"nope":1}', "" },
      "\n"
    ),
    { LIB_NVIM_DIR = lib_dir, SPEC_ROOT = "/spec/root" }
  )
  eq(child.code, 0, "the host ends cleanly when its input ends; stderr: " .. tostring(child.stderr))
  local lines = {}
  for l in (child.stdout:gsub("\r", "")):gmatch("[^\n]+") do
    lines[#lines + 1] = l
  end
  eq(lines[1], "ready\t1")
  local hello = vim.json.decode(lines[2]:match("^1\t(.*)$"))
  eq({ hello.kind, hello.plugin, hello.vault.id }, { "spec.hello", "spec.nvim", "root" })
  local echo = vim.json.decode(lines[3]:match("^2\t(.*)$"))
  eq({ echo.kind, echo.text }, { "spec.echo", "x" })
  ok(echo.pid ~= uv.os_getpid(), "answered by the child, not by this process")
  eq(vim.json.decode(lines[4]:match("^3\t(.*)$")).code, "invalid_argument")
  eq(#lines, 4, "nothing else on stdout")
  has(child.stderr, "not a request")

  -- two questions to one process: the same process answers (the modules are loaded once)
  local twice =
    run_child('1\techo\t{"text":"a"}\n2\techo\t{"text":"b"}\n', { LIB_NVIM_DIR = lib_dir })
  local pids = {}
  for id, body in (twice.stdout:gsub("\r", "")):gmatch("(%d)\t([^\n]+)") do
    pids[id] = vim.json.decode(body).pid
  end
  ok(pids["1"] ~= nil and pids["1"] == pids["2"], "one process for both questions")

  -- the input ends at once: ready, then a clean exit
  local quiet = run_child("", { LIB_NVIM_DIR = lib_dir })
  eq(quiet.code, 0)
  eq((quiet.stdout:gsub("\r", "")), "ready\t1\n")

  -- the other places the template looks for lib.nvim: $LIB_NVIM_PATH and $REPOS_DIR/lib.nvim
  local via_path = run_child("", { LIB_NVIM_DIR = "", LIB_NVIM_PATH = lib_dir })
  eq(via_path.code, 0, "LIB_NVIM_PATH: " .. tostring(via_path.stderr))
  local repos = vim.fs.dirname(lib_dir)
  if vim.fs.basename(lib_dir) == "lib.nvim" then
    local via_repos = run_child("", { LIB_NVIM_DIR = "", LIB_NVIM_PATH = "", REPOS_DIR = repos })
    eq(via_repos.code, 0, "REPOS_DIR/lib.nvim: " .. tostring(via_repos.stderr))
  else
    H.skipped("contract_host: REPOS_DIR/lib.nvim", "the checkout is not called lib.nvim")
  end

  -- lib.nvim nowhere: exit code 2 and a message that names what to set; the editor's data folder is moved away too
  local empty = dir .. "/empty-data"
  vim.fn.mkdir(empty, "p")
  local lost = run_child("1\thello\t\n", {
    LIB_NVIM_DIR = "",
    LIB_NVIM_PATH = "",
    REPOS_DIR = "",
    XDG_DATA_HOME = empty,
    LOCALAPPDATA = empty,
  })
  eq(lost.code, 2, "no lib.nvim: exit 2; stdout " .. tostring(lost.stdout))
  has(lost.stderr, "lib.nvim not found for spec.nvim")
  has(lost.stderr, "LIB_NVIM_DIR")
  eq(lost.stdout, "", "and nothing on stdout, not even ready")

  vim.fn.delete(dir, "rf")
end
