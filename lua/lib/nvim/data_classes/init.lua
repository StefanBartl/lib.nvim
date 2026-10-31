---@module 'lib.nvim.data_classes'
---@brief The data classes of the areas on this device: the `areas.json` of the desktop apps, read fail-closed.
---@description
--- `areas.json` lives in the config folder of the app (tasks-desktop), per device, never in a vault: a vault is synced
--- and changed by pull requests, and a release written there could be set by a third party. Each area is `public`,
--- `internal` or `private`; an area without an entry is `unclassified`, and an unclassified area is released for
--- nothing that leaves the machine. This module reads that file the way
--- `tasks-desktop/crates/tasks-hub/src/classes.rs` does: the same path, the same two schemas, the same refusals.
---
--- Schema 1 (`"schema": 1`, keys are area names, an optional top-level `"default"`) is the classes of the vault
--- `main`. Schema 2 keys an entry by `<vault>:<area>` and may give a vault its own default
--- (`"vaults": {"work": {"default": "internal"}}`). A vault the file does not name has every area unclassified.
---
--- The text is parsed as strictly as serde_json parses it, not with `vim.json.decode`: that parser keeps the last of
--- a field written twice, reads `1.0` as `1` and takes a byte order mark, and `{"class":"private","class":"public"}`
--- would then release an area the hub keeps closed. Where the two could differ, the file is refused here.
---
--- One difference from the hub, on purpose: the hub does not start with a file it cannot use. A reader of a library
--- does not stop its caller, so a file that cannot be used classifies nothing and says why in `problem`.
---
---```lua
--- local data_classes = require("lib.nvim.data_classes")
---
--- local classes = data_classes.load() -- <config>/tasks-desktop/areas.json
--- if classes.problem then
---   -- nothing is released; tell the person why
--- end
--- classes:shown("lib.nvim")             --> "internal" | "public" | "private" | "unclassified"
--- classes:for_vault("work"):allows("x") --> false unless public or internal
---
--- local class, problem = data_classes.class_of_repo("E:/repos/lib.nvim")
---```

require("lib.nvim.data_classes.@types")

local utf8 = require("lib.lua.strings.utf8")
local read_bounded = require("lib.nvim.fs.read_bounded")
local clip = require("lib.nvim.contract.echo").clip

local uv = vim.uv or vim.loop

local M = {}

---The schema of `areas.json` that only knows the vault `main`.
M.SCHEMA = 1
---The schema whose keys are `<vault>:<area>`.
M.SCHEMA_VAULTS = 2
---The most areas a file may name.
M.MAX_AREAS = 1000
---The largest file that is read.
M.MAX_FILE_BYTES = 256 * 1024
---The vault of a file of schema 1.
M.MAIN_VAULT = "main"
---The folder of the app under the system config folder (`IDENTITY.app` of tasks-hub).
M.APP = "tasks-desktop"
---The variable that names the config folder instead (`IDENTITY.var("CONFIG_DIR")` of tasks-hub).
M.ENV_VAR = "TASKS_DESKTOP_CONFIG_DIR"
---The name of the file in the config folder.
M.FILE = "areas.json"

local MAIN = M.MAIN_VAULT
local MAX_AREAS = M.MAX_AREAS
local MAX_FILE_BYTES = M.MAX_FILE_BYTES

---serde_json refuses a value nested 128 levels deep.
local MAX_DEPTH = 127
local MAX_AREA_NAME = 128
local MAX_VAULT_NAME = 40

local CLASSES = { public = true, internal = true, private = true }
---The strictest class wins when several areas name one repository.
local RANK = { public = 1, internal = 2, private = 3 }

local ENTRY_FIELDS = { "class", "repo" }
local RULE_FIELDS = { "default" }
local FILE_FIELDS = { "schema", "default", "areas" }
local FILE_V2_FIELDS = { "schema", "vaults", "areas" }

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
ESCAPES.b, ESCAPES.f, ESCAPES.n, ESCAPES.r, ESCAPES.t = "\b", "\f", "\n", "\r", "\t"

-- -- names ----------------------------------------------------------------------------------------------------------

---How many characters a valid UTF-8 text has: every byte that is not a continuation byte starts one.
---@param s string
---@return integer
local function chars(s)
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

---Is `s` valid UTF-8 (what a Rust `&str` always is)?
---@param s string
---@return boolean
local function is_utf8(s)
  local i = 1
  while i <= #s do
    local len = utf8.valid_len(s, i)
    if not len then
      return false
    end
    i = i + len
  end
  return true
end

---`valid_area_name` of tasks-hub: one plain folder name, fit to be an area or a repository. Nothing that could climb
---out of a folder, name a drive, hide itself or break a comma separated list.
---@param name string
---@return boolean ok
---@return string|nil why
function M.valid_area_name(name)
  if type(name) ~= "string" or name == "" then
    return false, "must have 1 to 128 characters"
  end
  -- the hub's name is a `&str`: a name that is not UTF-8 is one it can never hold
  if not is_utf8(name) then
    return false, "is not valid UTF-8"
  end
  if chars(name) > MAX_AREA_NAME then
    return false, "must have 1 to 128 characters"
  end
  if name:sub(1, 1) == "." or name:find("[ %.]$") then
    return false, "must not start with a dot or end with a dot or a space"
  end
  -- a control character (Unicode Cc: U+0000-001F, U+007F-009F) or one a folder name may not have
  if name:find('[%z\1-\31\127/\\,:*?"<>|]') or name:find("\194[\128-\159]") then
    return false, "holds a character that is not allowed in a folder name"
  end
  return true, nil
end

---`known_vault_name` of classes.rs: `main`, or a name the list of vaults accepts (1 to 40 of ASCII letters, digits,
---dot, dash and underscore, not starting with a dot).
---@param name string
---@return boolean ok
---@return string|nil why
function M.valid_vault_name(name)
  if name == MAIN then
    return true, nil
  end
  if type(name) ~= "string" or name == "" or #name > MAX_VAULT_NAME then
    -- a name of more than 40 bytes is either too long or not ASCII: refused either way
    return false, "must have 1 to 40 characters"
  end
  if name:sub(1, 1) == "." or not name:find("^[A-Za-z0-9._-]+$") then
    return false,
      "may hold letters, digits, dot, dash and underscore, and does not start with a dot"
  end
  return true, nil
end

---A name as it is echoed in a refusal: short, valid UTF-8, printable, quoted.
---@param name string
---@return string
local function show(name)
  return '"' .. clip(name) .. '"'
end

-- -- JSON, as strictly as serde_json ----------------------------------------------------------------------------------

---A refusal of the file, told apart from a fault of this module.
local Refusal = {}

---@param why string
local function reject(why)
  error(setmetatable({ why = why }, Refusal), 0)
end

---@class (private) Lib.DataClasses.Json
---@field kind "null"|"bool"|"number"|"string"|"array"|"object"
---@field text? string  a number as written
---@field value? string  a string, decoded
---@field items? Lib.DataClasses.Json[]
---@field pairs? { [1]: string, [2]: Lib.DataClasses.Json }[]  every pair in order, a key twice kept twice

---Parse JSON text (valid UTF-8) into a tree that keeps duplicate keys and the spelling of numbers.
---@param text string
---@return Lib.DataClasses.Json
local function parse_strict(text)
  local at = 1
  local find, sub, byte = string.find, string.sub, string.byte

  local function skip()
    -- JSON white space, nothing more (not U+00A0, not a vertical tab, not a byte order mark)
    local _, e = find(text, "^[ \t\n\r]*", at)
    at = e + 1
  end

  local function digits()
    local _, e = find(text, "^%d*", at)
    at = e + 1
  end

  local function is_digit(c)
    return c ~= nil and c >= 48 and c <= 57
  end

  local function hex4()
    local part = sub(text, at, at + 3)
    if not part:find("^%x%x%x%x$") then
      reject("invalid \\u escape")
    end
    at = at + 4
    return tonumber(part, 16)
  end

  local function str()
    at = at + 1 -- the opening quote
    local parts = {}
    while true do
      local s = find(text, '[%z\1-\31"\\]', at)
      if not s then
        reject("unterminated string")
      end
      ---@cast s integer
      if s > at then
        parts[#parts + 1] = sub(text, at, s - 1)
      end
      local c = byte(text, s)
      at = s + 1
      if c == 34 then
        return table.concat(parts)
      end
      if c < 0x20 then
        reject("control character in string")
      end
      local e = sub(text, at, at)
      at = at + 1
      if ESCAPES[e] then
        parts[#parts + 1] = ESCAPES[e]
      elseif e == "u" then
        local first = hex4()
        if first >= 0xDC00 and first <= 0xDFFF then
          reject("lone surrogate in escape")
        end
        if first >= 0xD800 and first <= 0xDBFF then
          if sub(text, at, at + 1) ~= "\\u" then
            reject("lone surrogate in escape")
          end
          at = at + 2
          local second = hex4()
          if second < 0xDC00 or second > 0xDFFF then
            reject("lone surrogate in escape")
          end
          parts[#parts + 1] = utf8.encode(0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00))
        else
          parts[#parts + 1] = utf8.encode(first)
        end
      else
        reject("invalid escape")
      end
    end
  end

  local function number()
    local start = at
    if byte(text, at) == 45 then -- -
      at = at + 1
    end
    local c = byte(text, at)
    if c == 48 then
      at = at + 1
      if is_digit(byte(text, at)) then
        reject("leading zero")
      end
    elseif is_digit(c) then
      digits()
    else
      reject("invalid number")
    end
    if byte(text, at) == 46 then -- .
      at = at + 1
      if not is_digit(byte(text, at)) then
        reject("invalid number")
      end
      digits()
    end
    c = byte(text, at)
    if c == 101 or c == 69 then -- e E
      at = at + 1
      c = byte(text, at)
      if c == 43 or c == 45 then
        at = at + 1
      end
      if not is_digit(byte(text, at)) then
        reject("invalid number")
      end
      digits()
    end
    return { kind = "number", text = sub(text, start, at - 1) }
  end

  local function word(literal)
    if sub(text, at, at + #literal - 1) ~= literal then
      reject("invalid literal")
    end
    at = at + #literal
  end

  local value

  local function object(depth)
    at = at + 1
    local pairs_ = {}
    skip()
    if sub(text, at, at) == "}" then
      at = at + 1
      return { kind = "object", pairs = pairs_ }
    end
    while true do
      skip()
      if sub(text, at, at) ~= '"' then
        reject("a key must be a string")
      end
      local key = str()
      skip()
      if sub(text, at, at) ~= ":" then
        reject("expected a colon")
      end
      at = at + 1
      pairs_[#pairs_ + 1] = { key, value(depth + 1) }
      skip()
      local c = sub(text, at, at)
      at = at + 1
      if c == "}" then
        return { kind = "object", pairs = pairs_ }
      elseif c ~= "," then
        reject("expected a comma or the end of the object")
      end
    end
  end

  local function array(depth)
    at = at + 1
    local items = {}
    skip()
    if sub(text, at, at) == "]" then
      at = at + 1
      return { kind = "array", items = items }
    end
    while true do
      items[#items + 1] = value(depth + 1)
      skip()
      local c = sub(text, at, at)
      at = at + 1
      if c == "]" then
        return { kind = "array", items = items }
      elseif c ~= "," then
        reject("expected a comma or the end of the list")
      end
    end
  end

  ---@param depth integer
  ---@return Lib.DataClasses.Json
  value = function(depth)
    skip()
    local c = sub(text, at, at)
    if c == "{" or c == "[" then
      if depth >= MAX_DEPTH then
        reject("nested too deep")
      end
      return c == "{" and object(depth) or array(depth)
    elseif c == '"' then
      return { kind = "string", value = str() }
    elseif c == "t" or c == "f" then
      word(c == "t" and "true" or "false")
      return { kind = "bool" }
    elseif c == "n" then
      word("null")
      return { kind = "null" }
    elseif c == "-" or c:find("^%d$") then
      return number()
    end
    reject(c == "" and "unexpected end of the file" or "unexpected character")
    error("unreachable")
  end

  local top = value(0)
  skip()
  if at <= #text then
    reject("characters after the value")
  end
  return top
end

-- -- the shapes of classes.rs ---------------------------------------------------------------------------------------

---A serde struct with `deny_unknown_fields`: an object (a field twice is an error, so is a name that is not a field)
---or a list in the order of the fields (serde_json reads a struct from either; more elements than fields is an error).
---@param json Lib.DataClasses.Json
---@param names string[]
---@param what string
---@return table<integer, Lib.DataClasses.Json>  slots by field index; a field left out is absent
local function struct(json, names, what)
  local slots = {}
  if json.kind == "object" then
    for _, pair in ipairs(json.pairs) do
      local index
      for i, name in ipairs(names) do
        if name == pair[1] then
          index = i
          break
        end
      end
      if not index then
        reject(("%s: unknown field %s"):format(what, show(pair[1])))
      end
      if slots[index] ~= nil then
        reject(("%s: duplicate field %s"):format(what, pair[1]))
      end
      slots[index] = pair[2]
    end
    return slots
  elseif json.kind == "array" then
    if #json.items > #names then
      reject(what .. ": too many elements")
    end
    for i, item in ipairs(json.items) do
      slots[i] = item
    end
    return slots
  end
  reject(what .. ": expected an object")
  error("unreachable")
end

---A serde map with string keys: an object. A key twice is not an error, the last value wins; every value is read,
---also one a later duplicate replaces, so a bad one refuses the file.
---@generic T
---@param json Lib.DataClasses.Json|nil
---@param what string
---@param one fun(item: Lib.DataClasses.Json, key: string): T
---@return table<string, T> map
---@return integer count  distinct keys
local function map_of(json, what, one)
  if json == nil then
    reject(what .. ": missing")
  end
  ---@cast json Lib.DataClasses.Json
  if json.kind ~= "object" then
    reject(what .. ": expected an object")
  end
  local out, count = {}, 0
  for _, pair in ipairs(json.pairs) do
    local item = one(pair[2], pair[1])
    if out[pair[1]] == nil then
      count = count + 1
    end
    out[pair[1]] = item
  end
  return out, count
end

---A unit enum as serde_json reads it: the name as a text (`"public"`), or a map of exactly that name to `null`
---(`{"public":null}`, the externally tagged form of a unit variant).
---@param json Lib.DataClasses.Json|nil
---@param what string
---@return Lib.DataClasses.Class
local function as_class(json, what)
  if json and json.kind == "string" and CLASSES[json.value] then
    return json.value
  end
  if json and json.kind == "object" and #json.pairs == 1 then
    local name, unit = json.pairs[1][1], json.pairs[1][2]
    if CLASSES[name] and unit.kind == "null" then
      return name
    end
  end
  reject(what .. ": not one of public, internal, private")
  error("unreachable")
end

---`Option<Class>`: left out or `null` is none.
---@param json Lib.DataClasses.Json|nil
---@param what string
---@return Lib.DataClasses.Class|nil
local function optional_class(json, what)
  if json == nil or json.kind == "null" then
    return nil
  end
  return as_class(json, what)
end

---A `u32`: a whole number written without a sign, a point or an exponent, up to 4294967295.
---@param json Lib.DataClasses.Json|nil
---@return integer
local function as_u32(json)
  local t = json and json.kind == "number" and json.text or ""
  local whole = t == "0" or t:find("^[1-9]%d*$") ~= nil
  if whole and (#t < 10 or (#t == 10 and t <= "4294967295")) then
    return tonumber(t) --[[@as integer]]
  end
  reject("schema: not a whole number")
  error("unreachable")
end

---@param json Lib.DataClasses.Json
---@param key string
---@return Lib.DataClasses.Entry
local function entry(json, key)
  local what = "area " .. show(key)
  local slots = struct(json, ENTRY_FIELDS, what)
  local cls, repo = slots[1], slots[2]
  if cls == nil then
    reject(what .. ": class is missing")
  end
  if repo ~= nil and repo.kind ~= "null" and repo.kind ~= "string" then
    reject(what .. ": repo is not a text")
  end
  return {
    class = as_class(cls, what),
    repo = repo and repo.kind == "string" and repo.value or nil,
  }
end

---A rule of a vault in schema 2, boxed so that "no default" is still a value of the map.
---@param json Lib.DataClasses.Json
---@param key string
---@return { default: Lib.DataClasses.Class|nil }
local function rule(json, key)
  local what = "vault " .. show(key)
  local slots = struct(json, RULE_FIELDS, what)
  return { default = optional_class(slots[1], what .. ": default") }
end

---@param t table<string, any>
---@return string[]
local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

---`AreaPolicy::new`: not too many, every name acceptable (the repo too).
---@param areas table<string, Lib.DataClasses.Entry>
---@param count integer
---@param where string
local function check_names(areas, count, where)
  if count > MAX_AREAS then
    reject(("%smore than %d areas"):format(where, MAX_AREAS))
  end
  for _, name in ipairs(sorted_keys(areas)) do
    local ok, why = M.valid_area_name(name)
    if not ok then
      reject(("%sarea %s: %s"):format(where, show(name), why))
    end
    local repo = areas[name].repo
    if repo ~= nil and not M.valid_area_name(repo) then
      reject(("%sarea %s: repo %s is not a plain name"):format(where, show(name), show(repo)))
    end
  end
end

---@param name string
local function known_vault(name)
  local ok, why = M.valid_vault_name(name)
  if not ok then
    reject(("vault %s: %s"):format(show(name), why))
  end
end

---@class (private) Lib.DataClasses.VaultTable
---@field areas table<string, Lib.DataClasses.Entry>
---@field count integer
---@field default Lib.DataClasses.Class|nil

---The vaults of a file: `Classes::load` without the reading.
---@param text string
---@return table<string, Lib.DataClasses.VaultTable> vaults
---@return integer schema
local function tables_of(text)
  local top = parse_strict(text)
  if top.kind ~= "object" then
    reject("expected an object")
  end
  -- `Peek`: the schema alone (the struct below refuses what does not belong)
  local schemas = {}
  for _, pair in ipairs(top.pairs) do
    if pair[1] == "schema" then
      schemas[#schemas + 1] = pair[2]
    end
  end
  if #schemas ~= 1 then
    reject(#schemas == 0 and "schema is missing" or "duplicate field schema")
  end
  local schema = as_u32(schemas[1])

  if schema == M.SCHEMA then
    local slots = struct(top, FILE_FIELDS, "areas.json")
    local default = optional_class(slots[2], "default")
    local areas, count = map_of(slots[3], "areas", entry)
    check_names(areas, count, "")
    return { [MAIN] = { areas = areas, count = count, default = default } }, schema
  elseif schema == M.SCHEMA_VAULTS then
    local slots = struct(top, FILE_V2_FIELDS, "areas.json")
    -- `vaults` has a default: left out is empty, `null` is not a map
    local rules = {}
    if slots[2] ~= nil then
      rules = map_of(slots[2], "vaults", rule)
    end
    local all, total = map_of(slots[3], "areas", entry)
    if total > MAX_AREAS then
      reject(("more than %d areas"):format(MAX_AREAS))
    end
    ---@type table<string, Lib.DataClasses.VaultTable>
    local grouped = {}
    for _, vault in ipairs(sorted_keys(rules)) do
      known_vault(vault)
      grouped[vault] = { areas = {}, count = 0 }
    end
    for _, key in ipairs(sorted_keys(all)) do
      local colon = key:find(":", 1, true)
      if not colon then
        reject(("key %s is not <vault>:<area>"):format(show(key)))
      end
      ---@cast colon integer
      local vault, area = key:sub(1, colon - 1), key:sub(colon + 1)
      known_vault(vault)
      local group = grouped[vault]
      if not group then
        group = { areas = {}, count = 0 }
        grouped[vault] = group
      end
      -- distinct keys of the map are distinct (vault, area) pairs: no area is counted twice
      group.areas[area] = all[key]
      group.count = group.count + 1
    end
    for _, vault in ipairs(sorted_keys(grouped)) do
      local group = grouped[vault]
      check_names(group.areas, group.count, ("vault %s: "):format(show(vault)))
      group.default = rules[vault] and rules[vault].default
    end
    return grouped, schema
  end
  reject(("schema %d is not %d or %d"):format(schema, M.SCHEMA, M.SCHEMA_VAULTS))
  error("unreachable")
end

-- -- what a caller asks ---------------------------------------------------------------------------------------------

local Policy = {}
Policy.__index = Policy

---@param t Lib.DataClasses.VaultTable|nil
---@return Lib.DataClasses.Policy
local function new_policy(t)
  t = t or { areas = {}, count = 0 }
  return setmetatable({ _areas = t.areas, _count = t.count, _default = t.default }, Policy)
end

function Policy:shown(area)
  -- an area a caller could not work out (nil, a number) is not "an area the file does not name": no default for it
  if type(area) ~= "string" then
    return "unclassified"
  end
  local e = self._areas[area]
  return (e and e.class) or self._default or "unclassified"
end

function Policy:allows(area)
  local shown = self:shown(area)
  return shown == "public" or shown == "internal"
end

function Policy:entry(area)
  local e = type(area) == "string" and self._areas[area] or nil
  return e and { class = e.class, repo = e.repo } or nil
end

function Policy:repo_of(area)
  local e = type(area) == "string" and self._areas[area] or nil
  return e and e.repo or nil
end

function Policy:default()
  return self._default
end

function Policy:areas()
  return sorted_keys(self._areas)
end

---@param self Lib.DataClasses.Policy
---@param all string[]
---@param shown Lib.DataClasses.Shown
---@return string[]
local function filter_shown(self, all, shown)
  local out = {}
  for _, area in ipairs(all) do
    if self:shown(area) == shown then
      out[#out + 1] = area
    end
  end
  return out
end

function Policy:unclassified(all)
  return filter_shown(self, all, "unclassified")
end

function Policy:private_areas(all)
  return filter_shown(self, all, "private")
end

function Policy:len()
  return self._count
end

function Policy:is_empty()
  return self._count == 0
end

local Classes = {}
Classes.__index = Classes

---@param vaults table<string, Lib.DataClasses.VaultTable>
---@param fields { problem?: string, kind?: Lib.DataClasses.ProblemKind, missing?: boolean, path?: string, schema?: integer }
---@return Lib.DataClasses.Classes
local function new_classes(vaults, fields)
  return setmetatable({
    _vaults = vaults,
    problem = fields.problem,
    kind = fields.kind,
    missing = fields.missing == true,
    path = fields.path,
    schema = fields.schema,
  }, Classes)
end

function Classes:for_vault(vault)
  return new_policy(self._vaults[vault or MAIN])
end

function Classes:shown(area, vault)
  return self:for_vault(vault):shown(area)
end

function Classes:allows(area, vault)
  return self:for_vault(vault):allows(area)
end

function Classes:vaults()
  return sorted_keys(self._vaults)
end

---The class of a repository: of the areas whose entry names it, the strictest. Only an entry's `repo` field (compared
---with the last part of `repo` as given) releases a repository. An entry without a `repo` field whose area name equals
---the repository's name (a hand-written file often leaves `repo` out) can only make it stricter, never release it: with
---no `repo` match the repository stays `unclassified`. A repository no entry names is `unclassified`: the `default` of a
---vault is a choice for its areas, and which area a repository belongs to only an entry says.
function Classes:class_of_repo(repo, vault)
  local name = type(repo) == "string" and repo:gsub("[/\\]+$", ""):match("[^/\\]*$") or ""
  local matches, worst, by_repo = {}, nil, false
  if name == "" then
    return "unclassified", matches
  end
  for _, v in ipairs(vault and { vault } or self:vaults()) do
    local t = self._vaults[v]
    if t then
      for _, area in ipairs(sorted_keys(t.areas)) do
        local e = t.areas[area]
        local by = (e.repo == name and "repo") or (e.repo == nil and area == name and "name") or nil
        if by then
          by_repo = by_repo or by == "repo"
          matches[#matches + 1] = { vault = v, area = area, class = e.class, by = by }
          if worst == nil or RANK[e.class] > RANK[worst] then
            worst = e.class
          end
        end
      end
    end
  end
  if not by_repo then
    return "unclassified", matches
  end
  return worst or "unclassified", matches
end

-- -- the file -------------------------------------------------------------------------------------------------------

---@param opts Lib.DataClasses.Opts|nil
---@param name string
---@return string|nil  a value that is set and not empty
local function getenv(opts, name)
  local value
  if opts and opts.env then
    value = opts.env[name]
  else
    value = uv.os_getenv(name)
  end
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

---The config folder of the app on this device, as `appkit_hub::config::config_dir` finds it: the variable
---`TASKS_DESKTOP_CONFIG_DIR` when it is set; else `%APPDATA%\tasks-desktop` on Windows,
---`~/Library/Application Support/tasks-desktop` on macOS, `$XDG_CONFIG_HOME/tasks-desktop` (or
---`~/.config/tasks-desktop`) elsewhere.
---@param opts? Lib.DataClasses.Opts
---@return string|nil dir
---@return string|nil err  why there is none
function M.config_dir(opts)
  opts = opts or {}
  local env_var = opts.env_var or M.ENV_VAR
  local own = getenv(opts, env_var)
  if own then
    return own, nil
  end
  local system = opts.os
  if system == nil then
    if require("lib.nvim.cross.platform.is_windows")() then
      system = "windows"
    elseif require("lib.nvim.cross.platform.is_macos")() then
      system = "macos"
    else
      system = "linux"
    end
  end
  local base, missing
  if system == "windows" then
    base, missing = getenv(opts, "APPDATA"), "APPDATA"
  elseif system == "macos" then
    local home = getenv(opts, "HOME")
    base, missing = home and vim.fs.joinpath(home, "Library", "Application Support"), "HOME"
  else
    local home = getenv(opts, "HOME")
    base = getenv(opts, "XDG_CONFIG_HOME") or (home and vim.fs.joinpath(home, ".config"))
    missing = "XDG_CONFIG_HOME and HOME"
  end
  if not base then
    return nil, ("no config folder: %s not set, nor %s"):format(missing, env_var)
  end
  return vim.fs.joinpath(base, opts.app or M.APP), nil
end

---The file that `load` reads: `opts.path`, else `<opts.dir>/areas.json`, else `<config_dir(opts)>/areas.json`.
---@param opts? Lib.DataClasses.Opts
---@return string|nil path
---@return string|nil err
function M.path(opts)
  opts = opts or {}
  if opts.path then
    return opts.path, nil
  end
  local dir, err = opts.dir, nil
  if not dir then
    dir, err = M.config_dir(opts)
  end
  if not dir then
    return nil, err
  end
  return vim.fs.joinpath(dir, M.FILE), nil
end

---The classes of the text of an `areas.json`. Text that cannot be used classifies nothing; `problem` says why.
---@param text string
---@param path? string
---@return Lib.DataClasses.Classes
local function from_text(text, path)
  if type(text) ~= "string" then
    return new_classes({}, { problem = "not a text", kind = "invalid", path = path })
  end
  if #text > MAX_FILE_BYTES then
    return new_classes({}, {
      problem = ("larger than %d KiB"):format(MAX_FILE_BYTES / 1024),
      kind = "invalid",
      path = path,
    })
  end
  -- Rust's `read_to_string` refuses what is not UTF-8 (an I/O error there, so `unreadable` here too)
  if not is_utf8(text) then
    return new_classes({}, { problem = "not valid UTF-8", kind = "unreadable", path = path })
  end
  local ok, vaults, schema = pcall(tables_of, text)
  if not ok then
    local fault = vaults --[[@as any]]
    ---@type string
    local why = getmetatable(fault) == Refusal and fault.why
      or ("not usable: %s"):format(tostring(fault))
    return new_classes({}, { problem = why, kind = "invalid", path = path })
  end
  return new_classes(vaults, { path = path, schema = schema })
end

---The classes of the text of an `areas.json` (`Classes::load` without the file).
---@param text string
---@return Lib.DataClasses.Classes
function M.parse(text)
  return from_text(text, nil)
end

---Read `areas.json` (see `path`). No file classifies nothing and is no problem; a file that exists and cannot be used
---classifies nothing either, and its `problem` is returned as the second value too.
---@param opts? Lib.DataClasses.Opts
---@return Lib.DataClasses.Classes classes
---@return string|nil problem
function M.load(opts)
  local path, err = M.path(opts)
  if not path then
    local classes = new_classes({}, { problem = err, kind = "no_config_dir" })
    return classes, classes.problem
  end
  local stat, _, errname = uv.fs_stat(path)
  if not stat and errname == "ENOENT" then
    return new_classes({}, { missing = true, path = path }), nil
  end
  local classes
  local text, read_err = read_bounded(path, MAX_FILE_BYTES)
  if text then
    classes = from_text(text, path)
  elseif read_err and read_err:find("^too large") then
    -- classes.rs: `Invalid`, like a file that is not right (it was opened, the size is what is wrong)
    classes = new_classes({}, {
      problem = ("larger than %d KiB"):format(MAX_FILE_BYTES / 1024),
      kind = "invalid",
      path = path,
    })
  else
    -- the reason without the path: the caller has it in `path`
    local why = (read_err or "cannot be read"):gsub(":%s.*$", "")
    classes = new_classes(
      {},
      { problem = "cannot read: " .. why, kind = "unreadable", path = path }
    )
  end
  return classes, classes.problem
end

---The class of a repository on this device: `load(opts)`, then `class_of_repo` (every vault unless `opts.vault`).
---A file that cannot be used makes every repository `unclassified`, and its problem is the second value.
---@param repo string  The folder of the repository, or its name.
---@param opts? Lib.DataClasses.Opts
---@return Lib.DataClasses.Shown class
---@return string|nil problem
---@return Lib.DataClasses.Match[] matches  The areas that name the repository.
function M.class_of_repo(repo, opts)
  local classes, problem = M.load(opts)
  local class, matches = classes:class_of_repo(repo, opts and opts.vault)
  return class, problem, matches
end

---@type Lib.DataClasses
return M
