---@module 'lib.nvim.contract.ops'
---@brief The write door of a machine contract: a list of operations, answered with one `<prefix>.result` document.
---@description
--- `ops.make{ doc, ops, ... }` returns the write door of ONE plugin's contract (`tasks-ops/1`, `rules-ops/1`). Moved
--- here from the shell of `tasks_nvim.ops` (tasks.nvim@6bc8d99); what an operation DOES (`set`, `new`, ...) stays with
--- the plugin as a handler.
---
--- A front end that is not the editor (an app, an agent) changes the source only through here. A request is
---
---   { "schema": 1, "client_op_id": "c-81f2", "dry_run": false, "ops": [ { "op": "set", ... }, ... ] }
---
--- and the answer is a `<prefix>.result` with one entry per operation (what happened, `ok`, `outcome`, an `error` that
--- says why, the version of the file before and after, for an undo the `inverse`: the handlers decide).
---
--- Rules the door keeps:
---  - **the shape is checked first, for the whole request**: an unknown operation or field, a wrong type, too many
---    operations is `invalid_argument` and nothing runs. The fault that is told is the first in byte order, the same
---    in every process. After that every operation runs on its own: one that fails does not stop the others (this is
---    NOT all-or-nothing, and the answer never says "ok" for a part);
---  - **`dry_run`** is told to the handlers (`ctx.dry`); they check everything and write nothing;
---  - **a handler never takes the door down**: one that raises, or answers nothing, is an `internal` entry with the
---    message scrubbed and the root hidden; the others still run;
---  - **no path of this machine in an entry**: `failure` and the `internal` entry hide the root (`contract.doc`);
---  - the `finish` hook runs once at the end (the index of every area that changed, the catalogs): its failure is told
---    in the document (`finish_error`, `ok` false), never swallowed and never a throw after the writes. `ok` is judged
---    after it, on the entries as it left them;
---  - **an answer is never lost for one entry**: a value JSON cannot hold in an entry (`NaN`, a whole number of 2^53
---    or more, nesting deeper than the encoder allows) turns that entry into an `internal` one that says the operation
---    ran but cannot be reported. The others keep their answer, so a client does not repeat the writes.
---
---```lua
--- local door = require("lib.nvim.contract.ops").make({
---   doc = d,                                          -- lib.nvim.contract.doc
---   order = { "set", "new" },                         -- the order the messages name them in
---   ops = {
---     set = { fields = { id = "string", patch = "object", if_match = "string" }, run = do_set },
---     new = { fields = { title = "string", body = "string" }, run = do_new },
---   },
---   context = function(params, opts) return { root = opts.root } end,   -- or nil, err
---   finish = function(ctx, results) end,
--- })
--- methods.ops = door.method()                         -- the entry of contract.api
---```
---
--- Not its job: parsing the request line (`contract.api`), what an operation does.

require("lib.nvim.contract.ops.@types")

local echo = require("lib.nvim.contract.echo")
local errors = require("lib.nvim.contract.errors")
local json = require("lib.nvim.json.canonical")
local nul_safe = require("lib.lua.strings.core").nul_safe

local M = {}

---The sizes the door keeps unless the plugin says otherwise.
M.DEFAULT_LIMITS = { batch_ops = 100, client_op_id = 64 }

---The largest value of the `integer` field type (the smallest is 1).
local INTEGER_MAX = 999999

---The field types of an operation: how a value is checked and how a refusal names it.
---@type table<string, Lib.Contract.OpsType>
local TYPES = {
  string = {
    label = "text",
    is = function(value)
      return type(value) == "string"
    end,
  },
  object = {
    label = "an object",
    is = function(value)
      return type(value) == "table" and (next(value) == nil or not vim.islist(value))
    end,
  },
  strings = {
    label = "text or a list of text",
    is = function(value)
      if type(value) == "string" then
        return true
      end
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
  },
  integer = {
    label = ("a whole number from 1 to %d"):format(INTEGER_MAX),
    is = function(value)
      return type(value) == "number"
        and value == math.floor(value)
        and value >= 1
        and value <= INTEGER_MAX
    end,
  },
  boolean = {
    label = "true or false",
    is = function(value)
      return type(value) == "boolean"
    end,
  },
}

local clip = echo.clip

---A value as it is shown in a refusal: short, and never a dump of a big table.
---@param value any
---@return string
local function shown(value)
  if value == vim.NIL then
    return "null" -- a JSON `null`, not the userdata it is in Lua
  end
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then
    return clip(vim.inspect(value))
  end
  return "<" .. kind .. ">"
end

---Whether a value carries a character that must not reach a source from a front end: a control character (ESC and the
---rest of C0 but the tab and the line feed, DEL, the 8-bit C1 range), a Unicode line separator, or text that is not
---valid UTF-8 (a raw 0x9B byte is a CSI to an 8-bit terminal, an overlong form is an ESC or a line feed that
---the checks above do not see, and the editor would take the whole file for latin1). Other tools print the files to
---a terminal and parse them; the editor's own commands clean what they print, a text editor does not. A list is
---searched entry by entry.
---@param value any
---@return boolean
function M.has_control(value)
  if type(value) == "string" then
    return value:find("[%z\1-\8\11-\31\127]") ~= nil
      or value:find("\194[\128-\159]") ~= nil
      or value:find("\226\128[\168\169]") ~= nil
      or json.scrub_utf8(value) ~= value
  elseif type(value) == "table" and value ~= vim.NIL then
    for _, v in ipairs(value) do
      if M.has_control(v) then
        return true
      end
    end
  end
  return false
end

---Whether a text is longer than `max` characters (not bytes). A NUL counts as one character (`strchars` itself raises
---on a Lua string that holds one); `has_control` is what refuses it.
---@param s any
---@param max integer
---@return boolean
function M.too_long(s, max)
  return type(s) == "string" and vim.fn.strchars(nul_safe(s)) > max
end

---@param names table<string, any>
---@return string[]
local function sorted_names(names)
  local out = {}
  for name in pairs(names) do
    out[#out + 1] = tostring(name)
  end
  table.sort(out, json.bytes_less)
  return out
end

---@param cfg Lib.Contract.OpsConfig
---@return Lib.Contract.Ops
function M.make(cfg)
  if type(cfg) ~= "table" then
    error("contract.ops.make needs a table", 2)
  end
  local d = cfg.doc
  if
    type(d) ~= "table"
    or type(d.head) ~= "function"
    or type(d.seal) ~= "function"
    or type(d.redact) ~= "function"
    or type(d.kind) ~= "function"
  then
    error("contract.ops.make: doc must be a lib.nvim.contract.doc instance", 2)
  end
  if type(cfg.ops) ~= "table" then
    error("contract.ops.make: ops must be a table", 2)
  end
  for _, key in ipairs({ "context", "finish" }) do
    if cfg[key] ~= nil and type(cfg[key]) ~= "function" then
      error(("contract.ops.make: %s must be a function"):format(key), 2)
    end
  end
  local types = vim.tbl_extend("force", {}, TYPES)
  for name, def in pairs(cfg.types or {}) do
    if type(def) ~= "table" or type(def.is) ~= "function" then
      error(("contract.ops.make: type '%s' needs an `is` function"):format(tostring(name)), 2)
    end
    types[name] = { is = def.is, label = def.label or "a valid value" }
  end
  for name, op in pairs(cfg.ops) do
    if type(op) ~= "table" or type(op.fields) ~= "table" or type(op.run) ~= "function" then
      error(("contract.ops.make: operation '%s' needs fields and run"):format(tostring(name)), 2)
    end
    for field, kind in pairs(op.fields) do
      if not types[kind] then
        error(
          ("contract.ops.make: operation '%s' field '%s' has the unknown type '%s'"):format(
            tostring(name),
            tostring(field),
            tostring(kind)
          ),
          2
        )
      end
    end
  end
  if cfg.patterns then
    local problem = errors.check_patterns(cfg.patterns)
    if problem then
      error("contract.ops.make: " .. problem, 2)
    end
  end

  local limits = vim.tbl_extend("force", M.DEFAULT_LIMITS, cfg.limits or {})
  local names = cfg.order or sorted_names(cfg.ops)

  local door = { OPS = names, limits = limits }

  ---The entry of an operation that did not happen, from whatever came back (`contract.errors.classify`), the root
  ---hidden.
  ---@param root string|nil
  ---@param err any
  ---@param info? table
  ---@return table
  function door.failure(root, err, info)
    if type(root) == "string" and not (type(err) == "table" and err.code) then
      -- the root goes first, as in `run`: `classify` scrubs a text it cannot place token by token, which cuts a root
      -- with a space in it in the middle, and what is left of it is no root any more
      err = d.redact(root, errors.text(err))
    end
    local e = vim.deepcopy(errors.classify(err, info, { patterns = cfg.patterns }))
    e.message = errors.text(e.message == nil and e.code or e.message) -- as `contract.doc` does for an error document
    if type(root) == "string" then
      e.message = d.redact(root, e.message)
    end
    if e.details then
      e.details = json.object(e.details)
    end
    return { ok = false, outcome = "failed", error = e }
  end

  ---The entry of an operation refused with a code of its own.
  ---@param code string
  ---@param message string
  ---@param details? table
  ---@return table
  function door.refuse(code, message, details)
    local e = errors.fail(code, message)
    e.details = details and json.object(details) or nil
    return { ok = false, outcome = "failed", error = e }
  end

  ---The entries a document cannot hold (`NaN`, a whole number of 2^53 or more, nesting deeper than the encoder
  ---allows, a function) are replaced, in place, by an `internal` entry that says so: the operation ran, and the
  ---answer for the others must not be lost with it (a client that is told nothing repeats the writes). Each entry is
  ---tried at the place it has in the document, so the message names `$.results[n]...`.
  ---@param results table[]
  ---@param hidden fun(text: any): string
  ---@return boolean replaced
  local function replace_unreportable(results, hidden)
    local probe = { results = {} }
    for i = 1, #results do
      probe.results[i] = vim.NIL
    end
    local replaced = false
    for i, entry in ipairs(results) do
      probe.results[i] = entry
      local fits, why = pcall(json.encode, probe)
      probe.results[i] = vim.NIL
      if not fits then
        local was = type(entry) == "table" and entry or {}
        local lost = door.refuse(
          "internal",
          "the operation ran, but its entry cannot be reported: " .. hidden(why)
        )
        lost.n = i
        lost.op = type(was.op) == "string" and was.op or nil
        lost.changed_ids = type(was.changed_ids) == "table"
            and pcall(json.encode, was.changed_ids)
            and was.changed_ids
          or {}
        results[i] = lost
        replaced = true
      end
    end
    return replaced
  end

  ---Check the shape of a request, all of it, before anything runs.
  ---@param params any
  ---@return Lib.Contract.Error|nil err
  function door.check_shape(params)
    if type(params) ~= "table" then
      return errors.fail("invalid_argument", "the request must be an object")
    end
    local list = params.ops
    if list == nil then
      return errors.fail("invalid_argument", "ops: the list of operations is missing")
    end
    if type(list) ~= "table" or not vim.islist(list) then
      return errors.fail("invalid_argument", "ops: must be a list of operations")
    end
    if #list == 0 then
      return errors.fail("invalid_argument", "ops: the list of operations is empty")
    end
    if #list > limits.batch_ops then
      return errors.fail(
        "payload_too_large",
        ("ops: at most %d operations in one request, got %d"):format(limits.batch_ops, #list)
      )
    end
    local cid = params.client_op_id
    if
      cid ~= nil
      and (
        type(cid) ~= "string"
        or #cid < 1
        or #cid > limits.client_op_id
        or not cid:match("^[%w._:%-]+$")
      )
    then
      return errors.fail(
        "invalid_argument",
        ("client_op_id must be 1 to %d characters of letters, digits and . _ : -"):format(
          limits.client_op_id
        )
      )
    end
    if params.dry_run ~= nil and type(params.dry_run) ~= "boolean" then
      return errors.fail("invalid_argument", "dry_run must be true or false")
    end
    for i, op in ipairs(list) do
      if type(op) ~= "table" then
        return errors.fail("invalid_argument", ("ops[%d]: must be an object"):format(i))
      end
      local name = op.op
      local def = type(name) == "string" and cfg.ops[name] or nil
      if not def then
        return errors.fail(
          "invalid_argument",
          ("ops[%d]: unknown operation %s (operations: %s)"):format(
            i,
            shown(name),
            table.concat(names, ", ")
          )
        )
      end
      -- in the order of the names (`pairs` differs from one process to the next), a key that is no text by its text
      local fields = {}
      for key, value in pairs(op) do
        fields[#fields + 1] = { text = tostring(key), value = value }
      end
      table.sort(fields, function(a, b)
        return json.bytes_less(a.text, b.text)
      end)
      for _, field in ipairs(fields) do
        if field.text ~= "op" then
          local kind = def.fields[field.text]
          if not kind then
            return errors.fail(
              "invalid_argument",
              ("ops[%d] (%s): unknown field '%s' (fields: %s)"):format(
                i,
                name,
                clip(field.text),
                table.concat(sorted_names(def.fields), ", ")
              )
            )
          end
          -- a JSON `null` for a field is the same as leaving it out
          if field.value ~= vim.NIL and not types[kind].is(field.value) then
            return errors.fail(
              "invalid_argument",
              ("ops[%d] (%s): %s must be %s"):format(i, name, field.text, types[kind].label)
            )
          end
        end
      end
    end
    return nil
  end

  ---Run a request and answer it with a `<prefix>.result` document.
  ---@param params table   # The request without its `schema`: `{ client_op_id?, dry_run?, ops }`.
  ---@param opts? table    # Handed to `cfg.context`.
  ---@return table|nil doc
  ---@return Lib.Contract.Error|nil err
  function door.run(params, opts)
    opts = opts or {}
    local shape = door.check_shape(params)
    if shape then
      return nil, shape
    end
    local ctx, cerr
    if cfg.context then
      ctx, cerr = cfg.context(params, opts)
    else
      ctx = { root = opts.root }
    end
    if type(ctx) ~= "table" then
      if cerr then
        -- the reason of the hook is an error of the contract here too, not only for the caller that classifies it
        -- (a text, or a table without a code, as it comes)
        return nil, door.failure(opts.root, cerr).error
      end
      return nil, errors.fail("internal", "the operations have no context")
    end
    ctx.dry = params.dry_run == true
    local root = type(ctx.root) == "string" and ctx.root or nil
    local function hidden(text)
      local message = errors.text(text)
      return errors.scrub(root and d.redact(root, message) or message)
    end

    local results = {}
    for i, op in ipairs(params.ops) do
      -- a JSON `null` for a field of the operation is the same as leaving it out
      for key, value in pairs(op) do
        if value == vim.NIL then
          op[key] = nil
        end
      end
      local ran, entry = pcall(cfg.ops[op.op].run, op, ctx)
      if not ran then
        entry = door.refuse("internal", hidden(entry))
      elseif type(entry) ~= "table" then
        entry = door.refuse("internal", "the operation answered nothing")
      end
      entry.n = i
      entry.op = op.op
      entry.changed_ids = entry.changed_ids or {}
      results[#results + 1] = entry
    end

    local finish_error
    if cfg.finish then
      local finished, ferr = pcall(cfg.finish, ctx, results)
      if not finished then
        finish_error = hidden(ferr)
      end
    end

    -- `finish` may change the entries: `ok` is judged on what it left
    local all_ok = finish_error == nil
    for _, entry in ipairs(results) do
      if type(entry) ~= "table" or not entry.ok then
        all_ok = false
        break
      end
    end

    local doc = d.head(d.kind("result"), root)
    doc.client_op_id = params.client_op_id
    doc.dry_run = ctx.dry
    doc.ok = all_ok
    -- written once for the digest, and the answer of `contract.api` reuses that text: `doc.results` must not change
    -- after `run` returns
    doc.results = json.memo(results)
    doc.finish_error = finish_error
    local sealed, text = pcall(d.seal, doc, nil)
    if not sealed and replace_unreportable(results, hidden) then
      doc.ok = false
      sealed, text = pcall(d.seal, doc, nil)
    end
    if not sealed then
      return nil, errors.fail("internal", hidden(text))
    end
    return doc, nil
  end

  ---The entry of this door in the methods of `contract.api`: the fields of the request are its own, `null` is kept
  ---(it means "remove" in a patch).
  ---@return Lib.Contract.ApiMethod
  function door.method()
    return {
      flat = true,
      keep_null = true,
      params = { client_op_id = "string", dry_run = "boolean", ops = "object_list" },
      run = door.run,
    }
  end

  return door --[[@as Lib.Contract.Ops]]
end

return M
