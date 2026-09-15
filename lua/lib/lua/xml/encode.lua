---@module 'lib.lua.xml.encode'
--- Pure-Lua XML encoder — the counterpart to `lib.lua.xml.decode`, same
--- element-tree shape: `{ tag = "name", attrs = {...}, children = {...} }`.
---
---   local xml = require("lib.lua.xml")
---   xml.encode({ tag = "a", attrs = { id = "1" }, children = { "hi" } })
---   -- '<a id="1">hi</a>'
---   xml.encode.pretty(value)          -- multi-line, 2-space indent
---   xml.encode(value, { indent = 4 }) -- multi-line, 4-space indent
---
--- Unlike `lib.lua.yaml.encode` (whose block-style subset has no single-line
--- form), XML has no such restriction: `encode` with no `indent` produces one
--- compact line, exactly mirroring `lib.lua.json.encode`'s own
--- compact-by-default / `.pretty` convenience-wrapper API.
---
--- Semantics:
---   * a table with a string `tag` field is an element; `attrs` (table,
---     optional) and `children` (array of elements/strings, optional)
---   * a childless element (no `children`, or an empty array) self-closes:
---     `<tag/>`
---   * a single plain-string child stays inline: `<tag>text</tag>`
---   * `&`, `<`, `>` (and `"` inside attribute values) are escaped; nothing
---     else in this subset needs it (no CDATA emission -- plain escaping
---     covers every text/attribute case this encoder produces)
---   * cycles, or a child that is neither a string nor an element table ->
---     nil + error message
---
--- Errors are reported as `nil, err` — the encoder never throws.

local M = {}

local TEXT_ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }
local ATTR_ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

---@internal
---@param s string
---@return string
local function escape_text(s)
  return (s:gsub("[&<>]", TEXT_ESCAPES))
end

---@internal
---@param s string
---@return string
local function escape_attr(s)
  return (s:gsub('[&<>"]', ATTR_ESCAPES))
end

---@internal
--- Render `attrs` as `' name="value"'*`, sorted for deterministic output.
---@param attrs table<string, any>|nil
---@return string
local function encode_attrs(attrs)
  if type(attrs) ~= "table" then
    return ""
  end
  local names = {}
  for k in pairs(attrs) do
    names[#names + 1] = k
  end
  table.sort(names)

  local parts = {}
  for _, k in ipairs(names) do
    parts[#parts + 1] = (' %s="%s"'):format(k, escape_attr(tostring(attrs[k])))
  end
  return table.concat(parts)
end

---@internal
---@param el any
---@param indent integer|nil # nil = compact (no newlines/padding)
---@param level integer
---@param seen table
---@return string|nil encoded
---@return string|nil err
local function emit_element(el, indent, level, seen)
  if type(el) ~= "table" or type(el.tag) ~= "string" then
    return nil, "expected an element table with a string 'tag' field"
  end
  if seen[el] then
    return nil, "cannot encode cyclic element tree"
  end
  seen[el] = true

  local open = "<" .. el.tag .. encode_attrs(el.attrs)
  local children = el.children

  if type(children) ~= "table" or #children == 0 then
    seen[el] = nil
    return open .. "/>", nil
  end

  if #children == 1 and type(children[1]) == "string" then
    seen[el] = nil
    return open .. ">" .. escape_text(children[1]) .. "</" .. el.tag .. ">", nil
  end

  local child_pad = indent and ("\n" .. string.rep(" ", (level + 1) * indent)) or ""
  local close_pad = indent and ("\n" .. string.rep(" ", level * indent)) or ""

  local parts = {}
  for i = 1, #children do
    local child = children[i]
    if type(child) == "string" then
      if child:find("%S") then
        parts[#parts + 1] = escape_text(child)
      end
    else
      local enc, err = emit_element(child, indent, level + 1, seen)
      if not enc then
        return nil, err
      end
      parts[#parts + 1] = enc
    end
  end

  seen[el] = nil
  return open
    .. ">"
    .. child_pad
    .. table.concat(parts, child_pad)
    .. close_pad
    .. "</"
    .. el.tag
    .. ">",
    nil
end

--- Encode an element tree as XML text.
---@param value any
---@param opts? { indent?: integer } # nil/0 = one compact line (default)
---@return string|nil encoded
---@return string|nil err
function M.encode(value, opts)
  opts = opts or {}
  local indent = opts.indent
  if type(indent) == "number" then
    indent = indent > 0 and indent or nil
  else
    indent = nil
  end

  if type(value) ~= "table" or type(value.tag) ~= "string" then
    return nil, "expected an element table with a string 'tag' field at the top level"
  end

  return emit_element(value, indent, 0, {})
end

--- Convenience wrapper: multi-line output with 2-space indentation.
---@param value any
---@param opts? { indent?: integer } # `indent` defaults to 2 here
---@return string|nil encoded
---@return string|nil err
function M.pretty(value, opts)
  opts = opts or {}
  if opts.indent == nil then
    opts = { indent = 2 }
  end
  return M.encode(value, opts)
end

-- The module itself is callable: `xml.encode(value)` and
-- `xml.encode.pretty(value)` both work, mirroring lib.lua.json.encode.
setmetatable(M, {
  __call = function(_, value, opts)
    return M.encode(value, opts)
  end,
})

---@type Lib.Xml.Encode
return M
