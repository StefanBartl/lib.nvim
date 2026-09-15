---@module 'lib.lua.yaml.encode'
--- Pure-Lua YAML encoder — the counterpart to `lib.lua.yaml.simple_parse`,
--- covering exactly the same intentionally minimal subset (see this
--- namespace's `init.lua` doc comment): no anchors/aliases, no flow style
--- (`{}`/`[]`), no block scalars (`|`/`>`), no multi-document streams.
---
--- Encoder output is decoder input: every shape below is checked against
--- `simple_parse` in TESTS, not just visually inspected.
---
---   local yaml = require("lib.lua.yaml")
---   yaml.encode({ name = "Ana", tags = { "a", "b" } })
---   -- "name: Ana\ntags:\n  - a\n  - b"
---
--- Semantics:
---   * strings           -> bare when `simple_parse` would read it back
---                          unchanged, single-quoted otherwise (see
---                          `needs_quoting`); a string containing a literal
---                          newline is an error (nil + err) -- this subset
---                          has no block/fold scalar to represent one
---   * numbers            -> integers without a trailing ".0"; NaN/Inf are
---                          an error, matching `lib.lua.json.encode`
---   * booleans           -> true/false
---   * lib.lua.null.NULL  -> the bare word "null"
---   * tables             -> array-like -> a block sequence ("- item");
---                          map-like -> a block mapping ("key: value"),
---                          object keys sorted for deterministic output
---   * an empty nested table (`{}`) has no representation in this subset
---     (no flow style) -- it is emitted as a bare "key:"/"-" line, which
---     `simple_parse` reads back as an explicit null (its own documented
---     null-as-absence behavior, not a new asymmetry introduced here)
---   * a MULTI-KEY map inside a list is emitted as a bare "-" followed by a
---     more-indented block, per `simple_parse`'s own documented shorthand
---     limit ("- a: 1" only supports ONE key per line)
---   * cycles, functions, userdata (other than NULL), threads -> nil + error
---
--- Errors are reported as `nil, err` — the encoder never throws.

local null = require("lib.lua.null")

local M = {}

local DEFAULT_INDENT = 2

-- Matches `lib.lua.tables.path_flatten`'s own `max_depth` default -- without
-- this, a pathologically deep (but acyclic) nested table would overflow the
-- Lua call stack in `emit_value`/`emit_map`/`emit_array`'s mutual recursion
-- instead of failing cleanly with `nil, err`.
local MAX_DEPTH = 64

---@internal
--- Contiguous positive integer keys starting at 1 (Lua array semantics) --
--- same definition every other lib.lua encoder/decoder in this repo uses.
---@param v any
---@return boolean
local function is_array_like(v)
  if type(v) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(v) do
    i = i + 1
    if v[i] == nil then
      return false
    end
  end
  return true
end

local BARE_LOOKS_LIKE =
  { ["true"] = true, ["false"] = true, ["null"] = true, ["~"] = true, [""] = true }

---@internal
--- Whether a bare (unquoted) scalar string would round-trip through
--- `simple_parse`'s `coerce_scalar` unchanged. If not, it must be quoted.
---@param s string
---@return boolean
local function needs_quoting(s)
  if BARE_LOOKS_LIKE[s] then
    return true
  end
  if tonumber(s) ~= nil then
    return true
  end
  if s:find(": ", 1, true) or s:sub(-1) == ":" then
    return true
  end
  if s:sub(1, 1) == "-" and (s == "-" or s:sub(2, 2) == " ") then
    return true -- looks like a list-item marker, not a plain hyphenated word
  end
  if s:sub(1, 1) == "#" then
    return true -- would be read as a comment line
  end
  local first = s:sub(1, 1)
  if first == "'" or first == '"' or first == " " or s:sub(-1) == " " then
    return true
  end
  return false
end

---@internal
---@param n number
---@return string|nil encoded
---@return string|nil err
local function encode_number(n)
  if n ~= n then
    return nil, "cannot encode NaN"
  end
  if n == math.huge or n == -math.huge then
    return nil, "cannot encode Infinity"
  end
  ---@diagnostic disable-next-line: deprecated
  if (math.type and math.type(n) == "integer") or (n % 1 == 0 and math.abs(n) < 2 ^ 53) then
    return string.format("%.0f", n), nil
  end
  return string.format("%.14g", n), nil
end

---@internal
--- Encode a scalar (not a table) value.
---@param v any
---@return string|nil encoded
---@return string|nil err
local function encode_scalar(v)
  if null.is_null(v) then
    return "null", nil
  end
  local t = type(v)
  if t == "boolean" then
    return v and "true" or "false", nil
  end
  if t == "number" then
    return encode_number(v)
  end
  if t == "string" then
    if v:find("\n", 1, true) or v:find("\r", 1, true) then
      -- This subset has no block/fold scalar form (see the module doc
      -- comment): a literal newline inside a single-quoted or bare scalar
      -- would break onto its own physical line with no key/indent prefix,
      -- producing text `simple_parse` cannot read back -- reject instead of
      -- silently emitting YAML the module's own decoder would choke on.
      return nil, "cannot encode a string containing a newline in this YAML subset"
    end
    if needs_quoting(v) then
      return "'" .. v:gsub("'", "''") .. "'", nil
    end
    return v, nil
  end
  return nil, "cannot encode scalar of type '" .. t .. "'"
end

local emit_map, emit_array, emit_value

--- Append the encoded line(s) for `v` at `level`, under `head` (a map key)
--- or as a plain list item when `head` is nil.
---@internal
---@param v any
---@param head string|nil
---@param width integer
---@param level integer
---@param seen table
---@param out string[]
---@return string|nil err
emit_value = function(v, head, width, level, seen, out)
  if level > MAX_DEPTH then
    return ("max nesting depth (%d) exceeded"):format(MAX_DEPTH)
  end

  local pad = string.rep(" ", level * width)
  local label = head and (head .. ":") or "-"

  if null.is_null(v) then
    out[#out + 1] = pad .. label .. " null"
    return nil
  end

  if type(v) == "table" then
    if next(v) == nil then
      -- Empty table: no inline ("[]"/"{}") form in this subset -- see the
      -- module doc comment on why this reads back as an explicit null.
      out[#out + 1] = pad .. label
      return nil
    end
    out[#out + 1] = pad .. label
    if is_array_like(v) then
      return emit_array(v, width, level + 1, seen, out)
    end
    return emit_map(v, width, level + 1, seen, out)
  end

  local s, err = encode_scalar(v)
  if not s then
    return err
  end
  out[#out + 1] = pad .. label .. " " .. s
  return nil
end

---@internal
---@param tbl table
---@param width integer
---@param level integer
---@param seen table
---@param out string[]
---@return string|nil err
emit_map = function(tbl, width, level, seen, out)
  if seen[tbl] then
    return "cannot encode cyclic table"
  end
  seen[tbl] = true

  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  for _, k in ipairs(keys) do
    local err = emit_value(tbl[k], tostring(k), width, level, seen, out)
    if err then
      return err
    end
  end

  seen[tbl] = nil
  return nil
end

---@internal
---@param arr any[]
---@param width integer
---@param level integer
---@param seen table
---@param out string[]
---@return string|nil err
emit_array = function(arr, width, level, seen, out)
  if seen[arr] then
    return "cannot encode cyclic table"
  end
  seen[arr] = true

  for i = 1, #arr do
    -- A map item with more than one key cannot use the "- key: value"
    -- inline shorthand (simple_parse only reads ONE key that way) -- it
    -- needs a bare "-" followed by a more-indented block instead, which
    -- `emit_value` already produces for any table value. A single-key map
    -- item goes through the same bare-"-"-plus-block form for simplicity
    -- (still valid, still round-trippable -- just not the terser
    -- single-line "- key: value" the decoder also happens to accept).
    local err = emit_value(arr[i], nil, width, level, seen, out)
    if err then
      return err
    end
  end

  seen[arr] = nil
  return nil
end

--- Encode a Lua value as YAML text (this repo's minimal subset).
---@param value any
---@param opts? { indent?: integer }
---@return string|nil encoded
---@return string|nil err
function M.encode(value, opts)
  opts = opts or {}
  local width = opts.indent
  if type(width) ~= "number" or width < 1 then
    width = DEFAULT_INDENT
  end

  if type(value) ~= "table" then
    return encode_scalar(value)
  end

  if next(value) == nil then
    -- Mirrors simple_parse("") == {} -- the empty document round-trips.
    return "", nil
  end

  local out = {}
  local seen = {}
  local err
  if is_array_like(value) then
    err = emit_array(value, width, 0, seen, out)
  else
    err = emit_map(value, width, 0, seen, out)
  end
  if err then
    return nil, err
  end
  return table.concat(out, "\n"), nil
end

--- Convenience alias: `indent` is already this encoder's only style knob
--- (unlike JSON, there is no compact-vs-pretty distinction -- YAML has no
--- single-line block form), kept for API symmetry with
--- `lib.lua.json.encode.pretty`.
---@param value any
---@param opts? { indent?: integer }
---@return string|nil encoded
---@return string|nil err
function M.pretty(value, opts)
  return M.encode(value, opts)
end

-- The module itself is callable: `yaml.encode(value)` and
-- `yaml.encode.pretty(value)` both work, mirroring lib.lua.json.encode.
setmetatable(M, {
  __call = function(_, value, opts)
    return M.encode(value, opts)
  end,
})

---@type Lib.Yaml.Encode
return M
