---@module 'lib.lua.config.schema'
--- Declarative option schemas for plugin configs: unknown keys and wrong types
--- are reported, and the rejected part is left out of the result so the default
--- applies (ERR-50 / ERR-22).
---@description
--- Taken from filetree.nvim's `config/schema.lua`, minus everything specific to
--- filetree (the always-accepted `autocmds_enabled`, the per-feature registry).
---
--- `check` only looks: it never changes its input and never writes a default.
--- It returns the part of the value that passed; a rejected value comes back as
--- `nil` and one line in `issues`, so the caller (the config store, or later a
--- repairing layer like `lib.nvim.json.sanitize`) decides what takes its place.
---
--- Spec forms:
---   "boolean" | "number" | "string" | "table" | "function"
---                       one Lua type; `|` unites several, and the token
---                       `false` matches the literal `false`:
---                       "string|false" = a string, or `false` to switch off
---   "keymap"            a key, a list of keys, or `false` (unmapped)
---   { "number", min = 0, max = 10 }
---                       inclusive bounds; NaN and +-inf never pass
---   { "string", enum = { "a", "b" } }
---                       closed value set (applies to string values only)
---   { "table", fields = { key = spec, ... } }
---                       closed record: unknown keys are reported
---   { "table", of = spec }
---                       array or open map whose every value matches `spec`
---   { "table" }         any table (what an empty `{}` default infers to)
---
--- `infer(defaults, exceptions)` builds the record schema out of a `DEFAULTS`
--- table, so a plugin only writes down what a default value can not say.

local levenshtein = require("lib.lua.strings.distance").levenshtein
local tables = require("lib.lua.tables.core")

local M = {}

---Dotted path of `key` below `path` ("" is the root).
---@param path string
---@param key any
---@return string
local function child(path, key)
  if path == "" then
    return tostring(key)
  end
  return path .. "." .. tostring(key)
end

---Largest edit distance that still counts as a typo of a known key.
---@type integer
local TYPO_EDITS = 3

---`key` with the nearest known one as a hint when there is a plausible one
---(edit distance <= 3). A candidate whose length differs by more than that cannot be within it (the distance is
---at least the difference of the lengths), so it is not compared: an option name of 120 kB costs nothing instead
---of a table of `#name * #candidate` cells per known key.
---@param key any
---@param known table<string, any>
---@param prefix string  dotted path of the table `key` sits in, with a trailing dot (or "")
---@return string
function M.describe_unknown(key, known, prefix)
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local text = tostring(candidate)
    local d = math.abs(#name - #text) <= TYPO_EDITS and levenshtein(name, text) or TYPO_EDITS + 1
    -- on a tie the alphabetically first wins, so the hint does not depend on `pairs` order
    if
      d <= TYPO_EDITS
      and (
        best_distance == nil
        or d < best_distance
        or (d == best_distance and tostring(candidate) < tostring(best))
      )
    then
      best, best_distance = candidate, d
    end
  end
  if best then
    return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best)
  end
  return ("unknown option '%s%s'"):format(prefix, name)
end

---@class Lib.Config.Schema.Parsed
---@field types    table<string, boolean>  accepted `type()` names
---@field is_false boolean                 the literal `false` is accepted
---@field label    string                  human-readable, for messages

---@type table<string, Lib.Config.Schema.Parsed>
local parsed_cache = {}

---Parse the type union of a spec (cached per union string).
---@param union string
---@return Lib.Config.Schema.Parsed
local function parse_union(union)
  local hit = parsed_cache[union]
  if hit then
    return hit
  end
  local types, is_false, labels = {}, false, {}
  for token in union:gmatch("[^|]+") do
    if token == "false" then
      is_false = true
      labels[#labels + 1] = "false"
    else
      types[token] = true
      labels[#labels + 1] = token == "table" and "a table" or ("a " .. token)
    end
  end
  hit = { types = types, is_false = is_false, label = table.concat(labels, " or ") }
  parsed_cache[union] = hit
  return hit
end

---How a rejected value reads in a message: numbers and booleans as they are, a string quoted, anything else by its type.
---@param value any
---@return string
function M.describe_got(value)
  local t = type(value)
  if t == "number" or t == "boolean" then
    return tostring(value)
  end
  if t == "string" then
    return ("%q"):format(value)
  end
  return t
end

---Keys of `t` in a stable order, so the same input always reports in the same order.
---@param t table
---@return any[]
local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then
      return a < b
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local check_record

---Check one value against one spec. Returns the value to keep, or `nil` when it
---was rejected (an issue is appended). A table comes back as a new table; the
---input is never changed.
---@param value any
---@param spec Lib.Config.Schema.Spec
---@param path string
---@param issues string[]
---@return any
function M.check(value, spec, path, issues)
  local t = type(spec) == "table" and spec or { spec }
  local vt = type(value)

  -- A keymap field goes to a keymap registry, which takes a key, a list of keys
  -- or `false`. A plain "string|false" union would refuse the list form that
  -- already works.
  if t[1] == "keymap" then
    if value == false or vt == "string" then
      return value
    end
    if vt == "table" and tables.is_array(value) then
      local out = {}
      for i, lhs in ipairs(value) do
        if type(lhs) ~= "string" then
          issues[#issues + 1] = ("option '%s.%d' must be a string, got %s -- using the default"):format(
            path,
            i,
            M.describe_got(lhs)
          )
          return nil
        end
        out[i] = lhs
      end
      return out
    end
    issues[#issues + 1] = ("option '%s' must be a string, a list of strings or false, got %s -- using the default"):format(
      path,
      M.describe_got(value)
    )
    return nil
  end

  local p = parse_union(t[1])

  local matches = p.types[vt] or (value == false and p.is_false)
  if not matches then
    issues[#issues + 1] = ("option '%s' must be %s, got %s -- using the default"):format(
      path,
      p.label,
      M.describe_got(value)
    )
    return nil
  end

  if vt == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      issues[#issues + 1] = ("option '%s' must be a finite number, got %s -- using the default"):format(
        path,
        tostring(value)
      )
      return nil
    end
    if (t.min and value < t.min) or (t.max and value > t.max) then
      local bound = t.min and t.max and ("between %s and %s"):format(t.min, t.max)
        or t.min and (">= " .. t.min)
        or ("<= " .. t.max)
      issues[#issues + 1] = ("option '%s' must be a number %s, got %s -- using the default"):format(
        path,
        bound,
        tostring(value)
      )
      return nil
    end
    return value
  end

  if vt == "string" and t.enum then
    for _, allowed in ipairs(t.enum) do
      if value == allowed then
        return value
      end
    end
    local quoted = {}
    for _, allowed in ipairs(t.enum) do
      quoted[#quoted + 1] = ("%q"):format(allowed)
    end
    issues[#issues + 1] = ("option '%s' must be one of %s, got %s -- using the default"):format(
      path,
      table.concat(quoted, ", "),
      M.describe_got(value)
    )
    return nil
  end

  if vt == "table" then
    if t.fields then
      return check_record(value, t.fields, path, issues)
    end
    if t.of then
      -- A rejected element degrades the whole table: dropping one entry out of
      -- an array would leave a hole (or shift the rest), which is worse than
      -- falling back to the default list.
      local out = {}
      for _, k in ipairs(sorted_keys(value)) do
        local kept = M.check(value[k], t.of, child(path, k), issues)
        if kept == nil then
          return nil
        end
        out[k] = kept
      end
      return out
    end
  end

  return value
end

---Check `body` (a user-supplied table) against `fields`, one key at a time.
---Does not change `body`. An unknown key and a rejected value are left out of
---the result and reported, so the default applies -- never a silent merge of a
---value nothing reads, and never a crash from a value nothing expected.
---@param body table
---@param fields Lib.Config.Schema.Fields
---@param path string  dotted path of `body`, e.g. "features.trash" ("" for the root)
---@param issues string[]  appended to
---@return table clean
function M.check_record(body, fields, path, issues)
  local clean = {}
  local prefix = path == "" and "" or (path .. ".")
  for _, key in ipairs(sorted_keys(body)) do
    local spec = fields[key]
    if spec == nil then
      issues[#issues + 1] = M.describe_unknown(key, fields, prefix)
    else
      local kept = M.check(body[key], spec, child(path, key), issues)
      -- `false` is a real value ("string|false"); only a rejected one is nil.
      if kept ~= nil then
        clean[key] = kept
      end
    end
  end
  return clean
end
check_record = M.check_record

---The spec a default value implies.
---  * boolean, number, string, function -> that type
---  * a non-empty map                   -> a closed record of its keys
---  * a list or `{}`                    -> any table (the shape of a user's entries is not in the default)
---@param default any
---@return Lib.Config.Schema.Spec
local function infer_node(default)
  local t = type(default)
  if t ~= "table" then
    return t
  end
  if next(default) == nil or tables.is_array(default) then
    return { "table" }
  end
  local fields = {}
  for k, v in pairs(default) do
    fields[k] = infer_node(v)
  end
  return { "table", fields = fields }
end

---Build the record schema of a `DEFAULTS` table. `exceptions` maps a dotted
---path to the spec to use there instead of (or in addition to) what the default
---says: a `false` default that also takes a string, an enum, a bound, an open
---map, a key that has no default at all.
---@param defaults table
---@param exceptions? table<string, Lib.Config.Schema.Spec>
---@return Lib.Config.Schema.SpecTable
function M.infer(defaults, exceptions)
  local root = infer_node(defaults)
  if type(root) ~= "table" or not root.fields then
    root = { "table", fields = {} }
  end
  local paths = {}
  for path in pairs(exceptions or {}) do
    paths[#paths + 1] = path
  end
  -- Shorter paths first: an exception for a branch is in place before one for a key inside it.
  table.sort(paths, function(a, b)
    if #a ~= #b then
      return #a < #b
    end
    return a < b
  end)
  for _, path in ipairs(paths) do
    local keys = {}
    for key in path:gmatch("[^.]+") do
      keys[#keys + 1] = key
    end
    ---@type any
    local node = root
    for i = 1, #keys - 1 do
      node = type(node) == "table" and node.fields and node.fields[keys[i]] or nil
      if type(node) ~= "table" then
        error(("schema exception '%s': '%s' is not a record"):format(path, keys[i]), 2)
      end
    end
    if type(node) ~= "table" or not node.fields then
      error(("schema exception '%s': its parent is not a record"):format(path), 2)
    end
    node.fields[keys[#keys]] = (exceptions or {})[path]
  end
  return root
end

---@type Lib.Config.Schema
return M
