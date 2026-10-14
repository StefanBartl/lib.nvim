---@module 'lib.nvim.contract.api'
---@brief The one door of a machine contract: `call(method, request)` answers with a JSON document, never with a throw.
---@description
--- `api.make{ doc, methods, ... }` returns the dispatcher of ONE plugin's contract. Moved here from
--- `tasks_nvim.api` (tasks.nvim@921a0c4): the mechanics are generic, the table of methods is the plugin's.
---
--- Everything outside the engine (an app, an agent, CI) asks through here and gets the canonical bytes of one
--- document of the contract (`lib.nvim.contract.doc`): the answer, or an error document that says what went wrong in
--- a code that is stable (`invalid_argument`, `not_found`, `unsupported_schema`, `payload_too_large`, `io`,
--- `internal`, ...; `lib.nvim.contract.errors`) and whether asking again can help (`retryable`).
---
--- A request is a JSON object: `{ "schema": 1, "params": { ... } }`. `schema` may be left out (it is 1), a higher
--- one is `unsupported_schema`; `params` may be left out too. A parameter the method does not know is
--- `invalid_argument`: a request that is silently half-understood is worse than one that is refused. A request is
--- at most 256 KiB. A method with `flat = true` carries its parameters as the request's own fields (a write door),
--- and `keep_null = true` keeps a JSON `null` as `vim.NIL` (it means "remove" in a patch).
---
--- A method is `{ params = { name = type }, run = function, flat? = boolean, keep_null? = boolean,
--- required? = { name } }`. `run(params, opts)` answers a document table, or `nil` and an error: a `contract.errors`
--- table, or a text that `classify` turns into one, with the third value `info` (`{ code, retryable?, id, ... }`, as
--- `fs.with_lock` gives it) where the source knows the code; only a table counts as `info`. Types: `string`,
--- `boolean`, `integer`, `string_list`, `object_list`, `object`, `number`, and the plugin's own through `cfg.types`.
--- An `integer` or a `number` is finite and below 2^53 in magnitude, the numbers the contract's JSON can hold.
---
--- The checks of a request run in a fixed order, so the same request gets the same answer in every process: the
--- schema (a request of a newer schema is `unsupported_schema` whatever else it carries), the request's fields, the
--- types, the unknown parameters, the required ones. Where one check finds several faults, the alphabetically first
--- is the one told.
---
--- `call` does not raise, whatever a hook of the plugin does (`root_of`, a type function, `run`): a bug there is
--- answered as `internal` with the scrubbed message.
---
---```lua
--- local api = require("lib.nvim.contract.api").make({
---   doc = d,                                  -- lib.nvim.contract.doc
---   methods = {
---     hello = { params = {}, run = function(_, opts) return contract.hello(opts) end },
---     rule = {
---       params = { id = "string" }, required = { "id" },
---       run = function(p, opts) return contract.rule(p.id, opts) end,
---     },
---   },
---   engine_opts = { "root" },                 -- what `call`'s opts hand to `run`
---   root_of = function(opts) return resolve(opts) end,  -- the root to hide in an error
---   patterns = PATTERNS,                      -- the plugin's own error-message patterns (shape checked here)
--- })
--- local text, code = api.call("rule", '{"params":{"id":"LUA-12"}}', { root = root })
---```
---
--- Not its job: building a document (`contract.doc`, the plugin), the command line.

require("lib.nvim.contract.api.@types")

local errors = require("lib.nvim.contract.errors")
local json = require("lib.nvim.json.canonical")

local M = {}

---A request bigger than this is refused before it is parsed, unless the plugin says otherwise.
M.DEFAULT_MAX_REQUEST_BYTES = 256 * 1024

---The magnitude from which the contract's JSON refuses a number (`json.canonical`: a whole number of 2^53 or more
---would lose digits; infinity and NaN have no JSON at all). A parameter the method echoes into its answer must be
---one the encoder can write, or the client's bad input would come back as `internal`.
local NUMBER_LIMIT = 2 ^ 53

---The parameter types every contract has. A value is checked, never coerced.
---@type table<string, fun(value: any): boolean>
local TYPES = {
  string = function(value)
    return type(value) == "string"
  end,
  boolean = function(value)
    return type(value) == "boolean"
  end,
  integer = function(value)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) < NUMBER_LIMIT
  end,
  number = function(value)
    return type(value) == "number" and math.abs(value) < NUMBER_LIMIT -- also false for NaN
  end,
  object = function(value)
    return type(value) == "table" and (next(value) == nil or not vim.islist(value))
  end,
  string_list = function(value)
    if type(value) ~= "table" or not vim.islist(value) then
      return false
    end
    for _, v in ipairs(value) do
      if type(v) ~= "string" then
        return false
      end
    end
    return true
  end,
  object_list = function(value)
    if type(value) ~= "table" or not vim.islist(value) then
      return false
    end
    for _, v in ipairs(value) do
      if type(v) ~= "table" or (next(v) ~= nil and vim.islist(v)) then
        return false
      end
    end
    return true
  end,
}

---@param method Lib.Contract.ApiMethod
---@param key any
---@return boolean
local function known_field(method, key)
  return key == "schema"
    or (method.flat and method.params[key] ~= nil)
    or (not method.flat and key == "params")
end

---@param method Lib.Contract.ApiMethod
---@param key any
---@return boolean
local function known_param(method, key)
  return method.params[key] ~= nil
end

---The text of the first key of `tbl` that `is_known` does not accept, first in byte order: a request with several
---faults is told the same one in every process (`pairs` visits string keys in an order that differs from one
---process to the next). One pass, no sort, no allocation; a key that is no string (a request that is already a
---Lua table) is compared by the text it is shown with.
---@param tbl table
---@param method Lib.Contract.ApiMethod
---@param is_known fun(method: Lib.Contract.ApiMethod, key: any): boolean
---@return string|nil
local function first_unknown(tbl, method, is_known)
  local first
  for key in pairs(tbl) do
    if not is_known(method, key) then
      local text = tostring(key)
      if first == nil or json.bytes_less(text, first) then
        first = text
      end
    end
  end
  return first
end

---@param cfg Lib.Contract.ApiConfig
---@return Lib.Contract.Api
function M.make(cfg)
  if type(cfg) ~= "table" then
    error("contract.api.make needs a table", 2)
  end
  local d = cfg.doc
  if type(d) ~= "table" or type(d.error_doc) ~= "function" or type(d.encode) ~= "function" then
    error("contract.api.make: doc must be a lib.nvim.contract.doc instance", 2)
  end
  if type(cfg.methods) ~= "table" then
    error("contract.api.make: methods must be a table", 2)
  end
  local types = vim.tbl_extend("force", TYPES, cfg.types or {})
  for name, method in pairs(cfg.methods) do
    if
      type(method) ~= "table"
      or type(method.params) ~= "table"
      or type(method.run) ~= "function"
    then
      error(("contract.api.make: method '%s' needs params and run"):format(tostring(name)), 2)
    end
    for param, kind in pairs(method.params) do
      if not types[kind] then
        error(
          ("contract.api.make: method '%s' parameter '%s' has the unknown type '%s'"):format(
            name,
            tostring(param),
            tostring(kind)
          ),
          2
        )
      end
    end
    for _, param in ipairs(method.required or {}) do
      if method.params[param] == nil then
        error(
          ("contract.api.make: method '%s' requires '%s', which it has no parameter for"):format(
            name,
            tostring(param)
          ),
          2
        )
      end
    end
  end
  -- `nil` and `false` mean "no patterns of my own"; a malformed rule would throw from the error path of `call`
  if cfg.patterns then
    local problem = errors.check_patterns(cfg.patterns)
    if problem then
      error("contract.api.make: " .. problem, 2)
    end
  end

  local pass_through = cfg.engine_opts or { "root" }
  local root_of = cfg.root_of or function(engine_opts)
    return engine_opts.root
  end

  local api = {
    METHODS = cfg.methods,
    MAX_REQUEST_BYTES = cfg.max_request_bytes or M.DEFAULT_MAX_REQUEST_BYTES,
  }

  ---The names of the methods, sorted.
  ---@return string[]
  function api.methods()
    local out = {}
    for name in pairs(api.METHODS) do
      out[#out + 1] = name
    end
    table.sort(out, json.bytes_less) -- the order is told in a message: the same on every machine
    return out
  end

  ---The smallest valid error document, as text: for the moment the real one cannot be made (it did not encode, the
  ---host failed). It has no head, only the fields a client needs.
  ---@param code string
  ---@param message string
  ---@return string
  function api.minimal_error(code, message)
    return json.encode({
      code = code,
      kind = d.ERROR_KIND,
      message = message,
      plugin = d.PLUGIN,
      retryable = false,
      schema = d.SCHEMA,
    })
  end

  ---@param code string
  ---@param message string
  ---@return Lib.Contract.Error
  local function fail(code, message)
    return errors.fail(code, message)
  end

  ---@param name string
  ---@param request string|table|nil
  ---@return table|nil params
  ---@return Lib.Contract.Error|nil err
  local function parse_request(name, request)
    local method = api.METHODS[name]
    if not method then
      return nil,
        fail(
          "not_found",
          ("unknown method '%s' (methods: %s)"):format(name, table.concat(api.methods(), ", "))
        )
    end
    local req = request
    if type(request) == "string" then
      if #request > api.MAX_REQUEST_BYTES then
        return nil,
          fail("payload_too_large", ("a request is at most %d bytes"):format(api.MAX_REQUEST_BYTES))
      end
      if vim.trim(request) == "" then
        req = {}
      else
        local ok, decoded = pcall(
          vim.json.decode,
          request,
          method.keep_null and {} or { luanil = { object = true, array = true } }
        )
        if not ok then
          return nil, fail("invalid_argument", "the request is not valid JSON")
        end
        req = decoded
      end
    end
    if req == nil then
      req = {}
    end
    if type(req) ~= "table" or (next(req) ~= nil and vim.islist(req)) then
      return nil, fail("invalid_argument", "the request must be a JSON object")
    end
    -- a JSON `null` at the top level is the same as leaving the field out
    for key, value in pairs(req) do
      if value == vim.NIL then
        req[key] = nil
      end
    end
    -- the schema first: a request of a newer schema may carry a field (or, for a flat method, a parameter) this
    -- engine does not know, and that is version skew ("update the engine"), not a typo
    if req.schema ~= nil then
      if type(req.schema) ~= "number" then
        return nil, fail("invalid_argument", "schema must be a number")
      end
      -- a fraction, NaN or infinity: no schema, and the message below could not name them (`%d` prints a fraction cut
      -- and infinity as the smallest integer)
      if req.schema % 1 ~= 0 then
        return nil, fail("invalid_argument", "schema must be a whole number")
      end
      if req.schema > d.SCHEMA then
        return nil,
          {
            code = "unsupported_schema",
            message = ("the request asks for schema %.14g, this engine speaks %d: update the engine"):format(
              req.schema,
              d.SCHEMA
            ),
            retryable = false,
          }
      end
      if req.schema < 1 then
        return nil, fail("invalid_argument", "schema must be 1 or more")
      end
    end
    local unknown_field = first_unknown(req, method, known_field)
    if unknown_field then
      local fields = { "schema" }
      if method.flat then
        local own = vim.tbl_keys(method.params)
        table.sort(own, json.bytes_less)
        vim.list_extend(fields, own)
      else
        fields[2] = "params"
      end
      return nil,
        fail(
          "invalid_argument",
          ("unknown field '%s' in the request (fields: %s)"):format(
            unknown_field,
            table.concat(fields, ", ")
          )
        )
    end
    local params = req.params
    if method.flat then
      params = vim.tbl_extend("force", {}, req)
      params.schema = nil
    end
    if params == nil then
      params = {}
    end
    if type(params) ~= "table" or (next(params) ~= nil and vim.islist(params)) then
      return nil, fail("invalid_argument", "params must be a JSON object")
    end
    -- in the order of the names, so that of two wrong parameters the same one is told every time
    local known = {}
    for key in pairs(method.params) do
      known[#known + 1] = key
    end
    table.sort(known, json.bytes_less)
    for _, key in ipairs(known) do
      local kind = method.params[key]
      if params[key] ~= nil and not types[kind](params[key]) then
        return nil,
          fail("invalid_argument", ("parameter '%s' must be %s"):format(key, (kind:gsub("_", " "))))
      end
    end
    local unknown_param = first_unknown(params, method, known_param)
    if unknown_param then
      return nil,
        fail(
          "invalid_argument",
          ("%s takes no parameter '%s'%s"):format(
            name,
            unknown_param,
            #known > 0 and (" (parameters: " .. table.concat(known, ", ") .. ")") or ""
          )
        )
    end
    for _, key in ipairs(method.required or {}) do
      if params[key] == nil then
        return nil, fail("invalid_argument", ("%s needs the parameter %s"):format(name, key))
      end
    end
    return params, nil
  end

  ---The answer for an error: its document, or the smallest valid one when that cannot be made.
  ---@param err Lib.Contract.Error
  ---@param root any            # The root to hide (whatever `root_of` answered).
  ---@param indent any
  ---@return string text
  ---@return string code        # The code of `err` (`internal` when it has none that is text).
  local function error_text(err, root, indent)
    -- an error document that cannot be made or encoded (a root_of that answers a number, a doc of the plugin that
    -- raises) is a bug of ours; answer with the smallest valid one, never with a throw
    local made, text = pcall(function()
      return (d.encode(d.error_doc(err, root), { indent = indent }))
    end)
    local code = type(err) == "table" and type(err.code) == "string" and err.code or "internal"
    return made and text or api.minimal_error("internal", "cannot encode the error"), code
  end

  ---The request is parsed, `run` runs, the answer is encoded.
  ---@param name any
  ---@param request string|table|nil
  ---@param opts table
  ---@param engine_opts table
  ---@param root any
  ---@return string text
  ---@return string|nil code
  local function respond(name, request, opts, engine_opts, root)
    local indent = opts.indent
    name = tostring(name)
    local params, perr = parse_request(name, request)
    if not params then
      return error_text(perr or fail("internal", "no parameters"), root, indent)
    end
    local ok, result, err, info = pcall(api.METHODS[name].run, params, engine_opts)
    if not ok then
      return error_text(fail("internal", errors.scrub(errors.text(result))), root, indent)
    end
    if not result then
      -- `info` is the third value a function of the lib gives (`fs.with_lock`); only a table can be one
      local classified =
        errors.classify(err, type(info) == "table" and info or nil, { patterns = cfg.patterns })
      return error_text(classified, root, indent)
    end
    local text, eerr = d.encode(result, { indent = indent })
    if not text then
      return error_text(eerr or fail("internal", "cannot encode the document"), root, indent)
    end
    return text, nil
  end

  ---Everything `call` does, which may raise: it is `call` that does not.
  ---@param name any
  ---@param request string|table|nil
  ---@param opts table|nil
  ---@return string text
  ---@return string|nil code
  local function answer(name, request, opts)
    opts = opts or {}
    local engine_opts = {}
    for _, key in ipairs(pass_through) do
      engine_opts[key] = opts[key]
    end
    -- the root is only for hiding it in a message: a source that cannot be found is named in the message the
    -- engine gives, and the path the caller handed in is still a path of this machine
    local root = root_of(engine_opts, opts)
    local done, text, code = pcall(respond, name, request, opts, engine_opts, root)
    if done then
      return text, code
    end
    -- a hook of the plugin raised (a type function on an odd value, a name with an `__tostring` that raises): a bug of
    -- the plugin, told as `internal` in a document that still hides the root
    return error_text(fail("internal", errors.scrub(errors.text(text))), root, opts.indent)
  end

  ---Answer one request. Never raises: a `root_of` or a type function of the plugin that raises, an `opts` that is no
  ---table, an error document that cannot be made, are all answered as `internal` with the scrubbed message.
  ---@param name string                     # The method.
  ---@param request? string|table           # The request as JSON text (or already decoded).
  ---@param opts? table                     # `indent` makes the text readable (golden files); `engine_opts` keys go to `run`.
  ---@return string text                    # The document: the answer, or an error document.
  ---@return string|nil code                # `nil` for an answer, else the error code.
  function api.call(name, request, opts)
    local done, text, code = pcall(answer, name, request, opts)
    if done then
      return text, code
    end
    -- not even the root could be had (a `root_of` that raises, an `opts` that cannot be read): the smallest valid
    -- document, with nothing to hide
    return api.minimal_error("internal", errors.scrub(errors.text(text))), "internal"
  end

  return api --[[@as Lib.Contract.Api]]
end

return M
