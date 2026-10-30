---@module 'lib.nvim.contract.errors'
---@brief The error vocabulary of a machine contract: a stable code, a message, whether asking again can help.
---@description
--- Moved here from `tasks_nvim.errors` (tasks.nvim@6bc8d99), with the one domain-specific part made a hook.
---
--- A plugin's functions answer `nil, "text"` and, where a caller has to act on the reason, a third value
--- `{ code = ..., ... }` (a compare-and-set: `conflict`, `locked`, `forbidden`; a file lock: `locked`, `lock_stuck`).
--- `classify` turns whatever came back into the error a document carries. An error string with no code is matched
--- against a short list of text patterns: the one fragile spot, until the code is given at every source. The patterns
--- of the shared parts (I/O, locks, "already exists") are built in; the patterns of a plugin's own messages are handed
--- in as `opts.patterns` and are tried first (`check_patterns` tells a malformed rule where it is handed in).
---
--- Whatever is not a string is made a text by `text`: a table by its own `__tostring` or its string `message`, any
--- other value by its type, never by its address. (`tasks_nvim.errors` used `tostring`, which printed `table: 0x...`,
--- a different text on every call.)
---
--- Codes (`M.CODES`): `invalid_argument` (the request or a value is wrong), `not_found` (id, method, source),
--- `conflict` (the file is not the version the caller saw), `exists` (the name is taken), `forbidden` (a link where a
--- file belongs), `locked` (another writer holds it right now; `retryable`), `lock_stuck` (a lock nobody will release),
--- `unsupported_schema`, `payload_too_large`, `rollback_incomplete` (a failed write could not be fully undone: the
--- message names the files), `io`, `internal`. The list is enforced: any other code (in `fail`, an error table,
--- `info.code`, a pattern) is answered as `internal` with a message that names it, never raised.
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

---@type table<string, true>
local KNOWN = {}
for _, code in ipairs(M.CODES) do
  KNOWN[code] = true
end

---Whether `code` is one of `M.CODES`.
---@param code any
---@return boolean
function M.is_code(code)
  return type(code) == "string" and KNOWN[code] == true
end

---A code that is not one of `M.CODES` (a typo, a plugin's own word) is answered as `internal`, never raised: the
---contract has a fixed list, and a wrong code must not take the host down from its error path. The message says
---which code was given, so the slip is found.
---@param code any
---@param message any
---@return string code
---@return any message
---@return boolean known
local function checked(code, message)
  if M.is_code(code) then
    return code, message, true
  end
  local given = type(code) == "string" and ("%q"):format(code) or ("of type " .. type(code))
  return "internal", ("unknown error code %s: %s"):format(given, M.text(message)), false
end

---@param code string  # one of `M.CODES`; any other is made `internal` (the message names it)
---@param message string
---@param retryable? boolean
---@return Lib.Contract.Error
function M.fail(code, message, retryable)
  local known
  code, message, known = checked(code, message)
  return { code = code, message = message, retryable = known and retryable == true }
end

---A token without everything up to its last `/lua/`. One search per token, on purpose: the single pattern
---`[^%s'"]*[/\]lua[/\]` backtracked over the whole token from every start, quadratic in a long one (an id of the
---request echoed in a message, up to 256 KiB: minutes of a blocked editor).
---@param token string
---@return string|nil cut    # `nil` keeps the token as it is
local function cut_token(token)
  local last, from = nil, 1
  while true do
    local s, e = token:find("[/\\]lua[/\\]", from)
    if not s then
      break
    end
    last, from = e, s + 1 -- `s + 1`: marks may overlap (`/lua/lua/`), the cut is after the last one
  end
  return last and token:sub(last + 1) or nil
end

---A Lua error message without where the plugin is installed: `<path>/lua/some_plugin/x.lua:12: boom` becomes
---`some_plugin/x.lua:12: boom`. The message of a bug of the engine says where it happened, which is useful, but the
---install path of this machine does not belong in a document.
---
---Limit: a token (what lies between whitespace or quotes) is cut at its last `/lua/`, so a path with a space keeps
---its head (`C:\Users\John Doe\...\lua\x\a.lua` becomes `C:\Users\John x\a.lua`), and a path with no `lua` directory
---is not touched at all. LuaJIT already shortens a chunk name of more than 59 characters to `...` plus its tail,
---which hides most of the head. Linear in the length of the text, a long token included.
---@param text string
---@return string
function M.scrub(text)
  return (text:gsub("[^%s'\"]+", cut_token))
end

---The text of whatever came back as an error: a string as it is, a number or boolean as it prints, a table by its
---own `__tostring` or its text `message`, anything else (a function, a userdata, a table with neither) a fixed text
---that names its type. Never an address (`table: 0x...` is different on every call and tells a client nothing) and
---never a throw (an error object whose `__tostring` or `message` raises is a value of unknown shape).
---@param value any
---@return string
function M.text(value)
  local kind = type(value)
  if kind == "string" then
    return value
  elseif kind == "number" or kind == "boolean" or kind == "nil" then
    return tostring(value)
  elseif kind == "table" then
    local meta = getmetatable(value)
    if type(meta) == "table" and rawget(meta, "__tostring") ~= nil then
      local printed, text = pcall(tostring, value)
      if printed and type(text) == "string" then
        return text
      end
    end
    local read, message = pcall(function()
      return value.message
    end)
    if read and type(message) == "string" then
      return message
    end
  end
  return "error value of type " .. kind
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

---Check the shape of a plugin's own patterns once, where they are handed in (`contract.api.make` does): a rule that
---is not `{ code = string, find = string[], retryable? }` would otherwise throw from the error path, only when a
---message falls through to it, and a rule without a code would answer an error document that has none.
---@param patterns any
---@return string|nil problem    # a message that names the first fault (no position: it is a value); `nil` if all is well
function M.check_patterns(patterns)
  if type(patterns) ~= "table" or not vim.islist(patterns) then
    return "patterns must be a list"
  end
  for i, rule in ipairs(patterns) do
    if type(rule) ~= "table" then
      return ("patterns[%d] must be a table"):format(i)
    end
    if type(rule.code) ~= "string" then
      return ("patterns[%d].code must be a string"):format(i)
    end
    if not M.is_code(rule.code) then
      return ("patterns[%d].code %q is not one of errors.CODES"):format(i, rule.code)
    end
    local find = rule.find
    local texts = type(find) == "table" and vim.islist(find)
    for _, needle in ipairs(texts and find or {}) do
      if type(needle) ~= "string" then
        texts = false
        break
      end
    end
    if not texts then
      return ("patterns[%d].find must be a list of strings"):format(i)
    end
  end
  return nil
end

---An error from below the contract, as the error a document carries.
---@param err any                    # the message, an error table (has a `code`), or any other value (made a text by `M.text`)
---@param info? table                # the third value some functions give: `{ code, retryable?, ... }`; anything but a table is ignored
---@param opts? Lib.Contract.ClassifyOpts
---@return Lib.Contract.Error
function M.classify(err, info, opts)
  if type(err) == "table" and err.code then
    if M.is_code(err.code) then
      return err
    end
    local failed = M.fail(err.code, err.message)
    failed.details = err.details
    return failed
  end
  local text = M.text(err)
  if type(info) == "table" and info.code then
    local details = {}
    for _, key in ipairs((opts and opts.detail_keys) or M.DETAIL_KEYS) do
      if info[key] ~= nil then
        details[key] = info[key]
      end
    end
    local code, message, known = checked(info.code, text)
    return {
      code = code,
      message = message,
      retryable = known and (info.retryable == true or code == "locked"),
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
