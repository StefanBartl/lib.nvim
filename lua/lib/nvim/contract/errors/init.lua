---@module 'lib.nvim.contract.errors'
---@brief The error vocabulary of a machine contract: a stable code, a message, whether asking again can help.
---@description
--- Moved here from `tasks_nvim.errors` (tasks.nvim@921a0c4), with the one domain-specific part made a hook.
---
--- A plugin's functions answer `nil, "text"` and, where a caller has to act on the reason, a third value
--- `{ code = ..., ... }` (a compare-and-set: `conflict`, `locked`, `forbidden`; a file lock: `locked`, `lock_stuck`).
--- `classify` turns whatever came back into the error a document carries. An error string with no code is matched
--- against a short list of text patterns: the one fragile spot, until the code is given at every source. The patterns
--- of the shared parts (I/O, locks, "already exists") are built in; the patterns of a plugin's own messages are handed
--- in as `opts.patterns` and are tried first.
---
--- Codes (`M.CODES`): `invalid_argument` (the request or a value is wrong), `not_found` (id, method, source),
--- `conflict` (the file is not the version the caller saw), `exists` (the name is taken), `forbidden` (a link where a
--- file belongs), `locked` (another writer holds it right now; `retryable`), `lock_stuck` (a lock nobody will release),
--- `unsupported_schema`, `payload_too_large`, `rollback_incomplete` (a failed write could not be fully undone: the
--- message names the files), `io`, `internal`.
---
--- Not its job: building the error document (`contract.doc` of the plugin), the plugin's own message patterns.

require("lib.nvim.contract.errors.@types")

local M = {}

---The codes a document may carry. Sorted.
---@type string[]
M.CODES = {
  "conflict",
  "exists",
  "forbidden",
  "internal",
  "invalid_argument",
  "io",
  "lock_stuck",
  "locked",
  "not_found",
  "payload_too_large",
  "rollback_incomplete",
  "unsupported_schema",
}

---@param code string
---@param message string
---@param retryable? boolean
---@return Lib.Contract.Error
function M.fail(code, message, retryable)
  return { code = code, message = message, retryable = retryable == true }
end

---A Lua error message without where the plugin is installed: `<path>/lua/some_plugin/x.lua:12: boom` becomes
---`some_plugin/x.lua:12: boom`. The message of a bug of the engine says where it happened, which is useful, but a path
---of this machine does not belong in a document.
---@param text string
---@return string
function M.scrub(text)
  return (text:gsub("[^%s'\"]*[/\\]lua[/\\]", ""))
end

---What a reader may learn from `info` besides the code: ids, keys and values, never a path.
---@type string[]
M.DETAIL_KEYS = { "id", "key", "expected", "actual", "written", "writes" }

---The patterns of the shared parts, tried after the plugin's own, in this order. A rule is `{ code, find, retryable? }`:
---it matches when the message contains one of the plain strings in `find`.
---@type Lib.Contract.ErrorPattern[]
local BUILTIN = {
  { code = "not_found", find = { "is not a directory", "no such" } },
  { code = "exists", find = { "already exists" } },
  { code = "rollback_incomplete", find = { "rollback incomplete" } },
  {
    code = "io",
    find = {
      "cannot list",
      "cannot read",
      "cannot write",
      "cannot create",
      "cannot update",
      "cannot lock",
      "permission",
    },
  },
  { code = "locked", find = { "is being written" }, retryable = true },
  { code = "lock_stuck", find = { "remove it by hand" } },
}

---@param text string
---@param rules Lib.Contract.ErrorPattern[]
---@return Lib.Contract.ErrorPattern|nil
local function match(text, rules)
  for _, rule in ipairs(rules) do
    for _, needle in ipairs(rule.find) do
      if text:find(needle, 1, true) then
        return rule
      end
    end
  end
  return nil
end

---An error from below the contract, as the error a document carries.
---@param err any                    # the message (or already an error table)
---@param info? table                # the third value some functions give: `{ code, retryable?, ... }`
---@param opts? Lib.Contract.ClassifyOpts
---@return Lib.Contract.Error
function M.classify(err, info, opts)
  if type(err) == "table" and err.code then
    return err
  end
  local text = tostring(err)
  if info and info.code then
    local details = {}
    for _, key in ipairs((opts and opts.detail_keys) or M.DETAIL_KEYS) do
      if info[key] ~= nil then
        details[key] = info[key]
      end
    end
    return {
      code = info.code,
      message = text,
      retryable = info.retryable == true or info.code == "locked",
      details = next(details) ~= nil and details or nil,
    }
  end
  local rule = (opts and opts.patterns and match(text, opts.patterns)) or match(text, BUILTIN)
  if rule then
    return M.fail(rule.code, text, rule.retryable == true)
  end
  return M.fail("internal", M.scrub(text), false)
end

---@type Lib.Contract.Errors
return M
