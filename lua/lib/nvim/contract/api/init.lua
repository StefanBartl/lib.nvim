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
--- A method is `{ params = { name = type }, run = fun(params, opts) -> doc|nil, err|nil, flat?, keep_null?,
--- required? = { name } }`. `run` answers a document table, or `nil` and an error (a `contract.errors` table, or a
--- text that `classify` turns into one). Types: `string`, `boolean`, `integer`, `string_list`, `object_list`,
--- `object`, `number`, and the plugin's own through `cfg.types`.
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
---   patterns = PATTERNS,                      -- the plugin's own error-message patterns
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
    return type(value) == "number" and value == math.floor(value)
  end,
  number = function(value)
    return type(value) == "number" and value == value
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
    table.sort(out)
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
    for key in pairs(req) do
      local known = key == "schema"
        or (method.flat and method.params[key] ~= nil)
        or (not method.flat and key == "params")
      if not known then
        local fields = { "schema" }
        if method.flat then
          local own = vim.tbl_keys(method.params)
          table.sort(own)
          vim.list_extend(fields, own)
        else
          fields[2] = "params"
        end
        return nil,
          fail(
            "invalid_argument",
            ("unknown field '%s' in the request (fields: %s)"):format(
              tostring(key),
              table.concat(fields, ", ")
            )
          )
      end
    end
    if req.schema ~= nil then
      if type(req.schema) ~= "number" then
        return nil, fail("invalid_argument", "schema must be a number")
      end
      if req.schema > d.SCHEMA then
        return nil,
          {
            code = "unsupported_schema",
            message = ("the request asks for schema %d, this engine speaks %d: update the engine"):format(
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
    local known = {}
    for key, kind in pairs(method.params) do
      known[#known + 1] = key
      if params[key] ~= nil and not types[kind](params[key]) then
        return nil,
          fail("invalid_argument", ("parameter '%s' must be %s"):format(key, (kind:gsub("_", " "))))
      end
    end
    table.sort(known)
    for key in pairs(params) do
      if method.params[key] == nil then
        return nil,
          fail(
            "invalid_argument",
            ("%s takes no parameter '%s'%s"):format(
              name,
              tostring(key),
              #known > 0 and (" (parameters: " .. table.concat(known, ", ") .. ")") or ""
            )
          )
      end
    end
    for _, key in ipairs(method.required or {}) do
      if params[key] == nil then
        return nil, fail("invalid_argument", ("%s needs the parameter %s"):format(name, key))
      end
    end
    return params, nil
  end

  ---Answer one request.
  ---@param name string                     # The method.
  ---@param request? string|table           # The request as JSON text (or already decoded).
  ---@param opts? table                     # `indent` makes the text readable (golden files); `engine_opts` keys go to `run`.
  ---@return string text                    # The document: the answer, or an error document.
  ---@return string|nil code                # `nil` for an answer, else the error code.
  function api.call(name, request, opts)
    opts = opts or {}
    local engine_opts = {}
    for _, key in ipairs(pass_through) do
      engine_opts[key] = opts[key]
    end
    -- the root is only for hiding it in a message: a source that cannot be found is named in the message the
    -- engine gives, and the path the caller handed in is still a path of this machine
    local root = root_of(engine_opts, opts)

    ---@param err Lib.Contract.Error
    ---@return string text
    ---@return string code
    local function error_text(err)
      local text = d.encode(d.error_doc(err, root), { indent = opts.indent })
      -- an error document that cannot be encoded is a bug of ours; answer with the smallest valid one
      return text or api.minimal_error("internal", "cannot encode the error"), err.code
    end

    name = tostring(name)
    local params, perr = parse_request(name, request)
    if not params then
      return error_text(perr or fail("internal", "no parameters"))
    end
    local ok, result, err = pcall(api.METHODS[name].run, params, engine_opts)
    if not ok then
      return error_text(fail("internal", errors.scrub(tostring(result))))
    end
    if not result then
      return error_text(errors.classify(err, nil, { patterns = cfg.patterns }))
    end
    local text, eerr = d.encode(result, { indent = opts.indent })
    if not text then
      return error_text(eerr or fail("internal", "cannot encode the document"))
    end
    return text, nil
  end

  return api --[[@as Lib.Contract.Api]]
end

return M
