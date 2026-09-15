---@module 'lib.lua.xml.decode'
--- Deliberately minimal, dependency-free XML decoder, pure Lua — same spirit
--- as `lib.lua.yaml`'s subset-not-spec decoder.
---
--- NOT spec-complete. Unsupported on purpose:
---   * namespaces (a prefixed tag like `<ns:tag>` is kept as the literal
---     string `"ns:tag"` -- no namespace resolution/binding)
---   * DTDs (a `<!DOCTYPE ...>` is skipped over, its internal subset is
---     never parsed for entities/elements)
---   * processing instructions other than a leading `<?xml ...?>`
---     declaration, which is skipped (not parsed for its own attributes)
---   * validating well-formedness beyond what parsing itself requires (tag
---     nesting/closing, one root element) -- no schema/DTD validation
---
--- Decoded shape: every element is
---   { tag = "name", attrs = { ["attr"] = "value", ... }, children = { ... } }
--- where `children` is an ARRAY mixing nested element tables and plain Lua
--- strings (text nodes, entities already decoded). This is a plain tree, not
--- an attempt to map onto a JSON-like object -- repeated sibling tags are
--- NOT collapsed into an array under one key, and there is no "the value of
--- this element" concept distinct from its children. See this namespace's
--- README for why (JSON/YAML's plain map/array IR doesn't fit XML's
--- element/attribute/mixed-content shape without an ambiguous, schema-
--- dependent translation).
---
--- A text node that is pure whitespace between element children is dropped
--- (insignificant whitespace from pretty-printed input); text inside a
--- leaf element's only child is kept verbatim, whitespace included.

local M = {}

-- =========================================================
-- Entities
-- =========================================================

local NAMED_ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

-- Matches `lib.lua.tables.path_flatten`'s own `max_depth` default -- without
-- this, a pathologically deep (but well-formed) element tree would overflow
-- the Lua call stack in `parse_element`'s recursion instead of failing
-- cleanly with `nil, err`.
local MAX_DEPTH = 64

---@internal
--- Encode a Unicode codepoint as UTF-8 bytes (no `utf8` stdlib dependency --
--- that library is a Lua 5.3+ addition LuaJIT does not ship).
---@param cp integer
---@return string
local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xc0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  elseif cp < 0x10000 then
    return string.char(
      0xe0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  end
  return string.char(
    0xf0 + math.floor(cp / 0x40000),
    0x80 + (math.floor(cp / 0x1000) % 0x40),
    0x80 + (math.floor(cp / 0x40) % 0x40),
    0x80 + (cp % 0x40)
  )
end

---@internal
--- Resolve the five predefined XML entities and `&#NN;`/`&#xHH;` numeric
--- references. An unrecognized named entity is left as-is (e.g. `&foo;`
--- passes through literally) -- this decoder has no DTD to resolve a custom
--- entity against.
---@param s string
---@return string
local function decode_entities(s)
  return (
    s:gsub("&(#?%w+);", function(entity)
      if entity:sub(1, 1) == "#" then
        local cp
        if entity:sub(2, 2):lower() == "x" then
          cp = tonumber(entity:sub(3), 16)
        else
          cp = tonumber(entity:sub(2))
        end
        return cp and utf8_encode(cp) or ("&" .. entity .. ";")
      end
      return NAMED_ENTITIES[entity] or ("&" .. entity .. ";")
    end)
  )
end

-- =========================================================
-- Parser state and low-level scanning
-- =========================================================

---@class Lib.Xml.DecodeState
---@field text string
---@field len integer
---@field pos integer # 1-based cursor into `text`, advanced by every helper below.
---@field depth integer # current element-nesting call depth, see MAX_DEPTH.

---@internal
---@param st Lib.Xml.DecodeState
local function skip_ws(st)
  local _, e = st.text:find("^%s*", st.pos)
  st.pos = e + 1
end

---@internal
--- Skip one `<!...>` markup declaration (a `<!DOCTYPE ...>`, comments are
--- handled separately by the caller before this is reached), respecting
--- nested `<...>` so a DOCTYPE with an internal subset
--- (`<!DOCTYPE x [ <!ENTITY ... > ]>`) doesn't stop at the first `>` inside it.
---@param st Lib.Xml.DecodeState
---@return string|nil err
local function skip_markup_decl(st)
  local depth = 0
  local i = st.pos
  while i <= st.len do
    local c = st.text:sub(i, i)
    if c == "<" then
      depth = depth + 1
    elseif c == ">" then
      depth = depth - 1
      if depth == 0 then
        st.pos = i + 1
        return nil
      end
    end
    i = i + 1
  end
  return "unterminated markup declaration"
end

---@internal
---@param st Lib.Xml.DecodeState
---@return string|nil name
---@return string|nil err
local function parse_name(st)
  local s, e, name = st.text:find("^([%w_:%.%-]+)", st.pos)
  if not s then
    return nil, "expected a tag/attribute name at position " .. st.pos
  end
  st.pos = e + 1
  return name, nil
end

---@internal
---@param st Lib.Xml.DecodeState
---@return table<string, string>|nil attrs
---@return string|nil err
local function parse_attrs(st)
  local attrs = {}
  while true do
    skip_ws(st)
    local c = st.text:sub(st.pos, st.pos)
    if c == ">" or c == "/" or c == "" then
      return attrs, nil
    end
    local name, nerr = parse_name(st)
    if nerr then
      return nil, nerr
    end
    ---@cast name string
    skip_ws(st)
    if st.text:sub(st.pos, st.pos) ~= "=" then
      return nil, ("expected '=' after attribute %q at position %d"):format(name, st.pos)
    end
    st.pos = st.pos + 1
    skip_ws(st)
    local quote = st.text:sub(st.pos, st.pos)
    if quote ~= '"' and quote ~= "'" then
      return nil, ("expected a quoted value for attribute %q at position %d"):format(name, st.pos)
    end
    st.pos = st.pos + 1
    local close = st.text:find(quote, st.pos, true)
    if not close then
      return nil, ("unterminated value for attribute %q"):format(name)
    end
    attrs[name] = decode_entities(st.text:sub(st.pos, close - 1))
    st.pos = close + 1
  end
end

-- =========================================================
-- Element tree
-- =========================================================

---@internal
--- Recursive: forward-declared so it can call itself for nested elements.
---@type fun(st: Lib.Xml.DecodeState): table|nil, string|nil
local parse_element

parse_element = function(st)
  if st.text:sub(st.pos, st.pos) ~= "<" then
    return nil, "expected '<' at position " .. st.pos
  end
  st.pos = st.pos + 1

  local name, nerr = parse_name(st)
  if nerr then
    return nil, nerr
  end
  ---@cast name string

  local attrs, aerr = parse_attrs(st)
  if aerr then
    return nil, aerr
  end
  skip_ws(st)

  if st.text:sub(st.pos, st.pos + 1) == "/>" then
    st.pos = st.pos + 2
    return { tag = name, attrs = attrs, children = {} }, nil
  end
  if st.text:sub(st.pos, st.pos) ~= ">" then
    return nil, ("expected '>' or '/>' for element <%s> at position %d"):format(name, st.pos)
  end
  st.pos = st.pos + 1

  local children = {}
  while true do
    if st.pos > st.len then
      return nil, ("unterminated element <%s> (missing </%s>)"):format(name, name)
    end

    if st.text:sub(st.pos, st.pos + 3) == "<!--" then
      local e = st.text:find("-->", st.pos, true)
      if not e then
        return nil, "unterminated comment"
      end
      st.pos = e + 3
    elseif st.text:sub(st.pos, st.pos + 8) == "<![CDATA[" then
      local e = st.text:find("]]>", st.pos, true)
      if not e then
        return nil, "unterminated CDATA section"
      end
      children[#children + 1] = st.text:sub(st.pos + 9, e - 1)
      st.pos = e + 3
    elseif st.text:sub(st.pos, st.pos + 1) == "</" then
      st.pos = st.pos + 2
      local close_name, cerr = parse_name(st)
      if cerr then
        return nil, cerr
      end
      skip_ws(st)
      if st.text:sub(st.pos, st.pos) ~= ">" then
        return nil, "expected '>' closing </" .. tostring(close_name) .. ">"
      end
      st.pos = st.pos + 1
      if close_name ~= name then
        return nil, ("mismatched closing tag: expected </%s>, got </%s>"):format(name, close_name)
      end
      return { tag = name, attrs = attrs, children = children }, nil
    elseif st.text:sub(st.pos, st.pos) == "<" then
      st.depth = st.depth + 1
      if st.depth > MAX_DEPTH then
        return nil, ("maximum element nesting depth (%d) exceeded"):format(MAX_DEPTH)
      end
      local child, cherr = parse_element(st)
      st.depth = st.depth - 1
      if cherr then
        return nil, cherr
      end
      children[#children + 1] = child
    else
      local next_lt = st.text:find("<", st.pos, true)
      local raw = next_lt and st.text:sub(st.pos, next_lt - 1) or st.text:sub(st.pos)
      st.pos = next_lt or (st.len + 1)
      local decoded = decode_entities(raw)
      if decoded:find("%S") then
        children[#children + 1] = decoded
      end
    end
  end
end

-- =========================================================
-- Public API
-- =========================================================

---Decode an XML document into a nested element tree (see the module doc
---comment for the exact shape and this decoder's intentional limits).
---@nodiscard
---@param text string
---@return table|nil root
---@return string|nil err
function M.decode(text)
  if type(text) ~= "string" then
    return nil, "invalid input: expected string"
  end

  local st = { text = text, len = #text, pos = 1, depth = 0 }
  skip_ws(st)

  if st.text:sub(st.pos, st.pos + 1) == "<?" then
    local e = st.text:find("?>", st.pos, true)
    if not e then
      return nil, "unterminated <?...?> declaration"
    end
    st.pos = e + 2
    skip_ws(st)
  end

  while true do
    if st.text:sub(st.pos, st.pos + 3) == "<!--" then
      local e = st.text:find("-->", st.pos, true)
      if not e then
        return nil, "unterminated comment"
      end
      st.pos = e + 3
      skip_ws(st)
    elseif st.text:sub(st.pos, st.pos + 1) == "<!" then
      local err = skip_markup_decl(st)
      if err then
        return nil, err
      end
      skip_ws(st)
    else
      break
    end
  end

  if st.text:sub(st.pos, st.pos) ~= "<" then
    return nil, "expected a root element at position " .. st.pos
  end

  local root, rerr = parse_element(st)
  if rerr then
    return nil, rerr
  end

  skip_ws(st)
  while st.pos <= st.len and st.text:sub(st.pos, st.pos + 3) == "<!--" do
    local e = st.text:find("-->", st.pos, true)
    if not e then
      return nil, "unterminated comment"
    end
    st.pos = e + 3
    skip_ws(st)
  end
  if st.pos <= st.len then
    return nil, "unexpected content after the root element at position " .. st.pos
  end

  return root, nil
end

---@type Lib.Xml.DecodeModule
return M
