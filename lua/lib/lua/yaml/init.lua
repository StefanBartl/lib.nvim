---@module 'lib.lua.yaml'
--- Deliberately minimal, dependency-free YAML-ish decoder, pure Lua.
---
--- This is NOT a spec-complete YAML parser. Unsupported on purpose:
---   * anchors/aliases (`&foo`, `*foo`)
---   * multi-document streams (`---` / `...` separators)
---   * flow style (`{a: 1}`, `[1, 2, 3]`)
---   * block scalars (`|`, `>`)
---   * inline comments (only a full line whose trimmed content starts with
---     `#` is treated as a comment; `key: value # note` keeps the `# note`
---     as part of the value)
---   * multi-key inline list records: `- a: 1` is supported as a single-key
---     shorthand producing `{ a = 1 }`; additional fields for the same
---     record must instead use a bare `-` line followed by a
---     more-indented `key: value` block
---
--- Indentation must use spaces. Each nesting level's lines must share
--- exactly one indent width; any line indented *more* than its block's
--- width starts a nested block, any line indented *less* closes the
--- current block. An indent that doesn't match any open level (e.g. a
--- dedent to a width that was never opened) is reported as an error.
---
--- YAML `null`/`~`/empty scalars cannot be stored as Lua `nil` inside a
--- table, so this decoder represents "null" by *omitting* the key (for
--- maps) or *skipping* the element (for lists) rather than using a
--- sentinel value. This means a missing map key can mean either "absent"
--- or "explicitly null" — callers that care about the distinction cannot
--- rely on `simple_parse`'s output alone.

---@type LibYaml
local M = {}

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param s string
---@return integer
local function leading_spaces(s)
  local sp = s:match("^( *)")
  return #sp
end

---Strip one layer of matching quotes, if present.
---@param s string
---@return string
local function strip_quotes(s)
  if #s >= 2 then
    local first, last = s:sub(1, 1), s:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
      return s:sub(2, -2)
    end
  end
  return s
end

-- Sentinel returned internally by `coerce_scalar` for YAML null/empty
-- values. Never leaks into `simple_parse`'s output: callers of
-- `coerce_scalar` always check for it and omit the key/element instead of
-- storing it (see module doc comment above for why).
local NULL = {}

---Coerce a raw (not-yet-trimmed) scalar string into a Lua value.
---@param raw string
---@return any value Lua value, or the internal NULL sentinel
local function coerce_scalar(raw)
  local s = trim(raw)
  if s == "" or s == "null" or s == "~" then
    return NULL
  end
  if s == "true" then
    return true
  end
  if s == "false" then
    return false
  end
  if (s:sub(1, 1) == '"' and s:sub(-1) == '"') or (s:sub(1, 1) == "'" and s:sub(-1) == "'") then
    return strip_quotes(s)
  end
  local num = tonumber(s)
  if num ~= nil then
    return num
  end
  return s
end

---True when `content` is a list-item line (`-` alone, or `- ...`).
---@param content string
---@return boolean
local function is_list_item(content)
  return content == "-" or content:sub(1, 2) == "- "
end

---@class YamlLine
---@field indent integer
---@field content string
---@field lineno integer

---@param text string
---@return YamlLine[]
local function tokenize(text)
  ---@type YamlLine[]
  local lines = {}
  local lineno = 0
  for raw_line in (text .. "\n"):gmatch("(.-)\n") do
    lineno = lineno + 1
    local line = raw_line:gsub("\r$", "")
    local content = trim(line)
    if content ~= "" and content:sub(1, 1) ~= "#" then
      lines[#lines + 1] = { indent = leading_spaces(line), content = content, lineno = lineno }
    end
  end
  return lines
end

---Decode a minimal-YAML-subset string into a nested Lua table.
---@nodiscard
---@param text string
---@return table|nil data
---@return string|nil err
function M.simple_parse(text)
  if type(text) ~= "string" then
    return nil, "invalid input: expected string"
  end

  local lines = tokenize(text)
  if #lines == 0 then
    return {}, nil
  end

  local pos = 1

  ---Parse one block (map or list) whose lines all share the same indent,
  ---which must be >= `min_indent`. Stops when a line dedents below that
  ---shared indent, or when input is exhausted.
  ---@param min_indent integer
  ---@return table|nil block
  ---@return string|nil err
  local function parse_block(min_indent)
    if pos > #lines or lines[pos].indent < min_indent then
      return {}, nil
    end

    local indent = lines[pos].indent
    local list_mode = is_list_item(lines[pos].content)
    local block = {}

    while pos <= #lines do
      local line = lines[pos]
      if line.indent < indent then
        break
      end
      if line.indent > indent then
        return nil, "bad indentation at line " .. line.lineno
      end

      if list_mode then
        if not is_list_item(line.content) then
          return nil, "expected list item ('- ...') at line " .. line.lineno
        end
        local rest = line.content == "-" and "" or trim(line.content:sub(3))
        pos = pos + 1

        if rest == "" then
          if pos <= #lines and lines[pos].indent > indent then
            local child, err = parse_block(indent + 1)
            if err then
              return nil, err
            end
            block[#block + 1] = child
          end
          -- else: explicit null list element -> omitted (see doc comment)
        else
          local key, val = rest:match("^([%w_%-]+):%s*(.*)$")
          if key then
            local v = coerce_scalar(val)
            local entry = {}
            if v ~= NULL then
              entry[key] = v
            end
            block[#block + 1] = entry
          else
            local v = coerce_scalar(rest)
            if v ~= NULL then
              block[#block + 1] = v
            end
          end
        end
      else
        local key, rest = line.content:match("^([^:]+):%s*(.*)$")
        if not key then
          return nil, "malformed line " .. line.lineno .. ": expected 'key: value'"
        end
        key = strip_quotes(trim(key))
        pos = pos + 1

        if rest == "" then
          if pos <= #lines and lines[pos].indent > indent then
            local child, err = parse_block(indent + 1)
            if err then
              return nil, err
            end
            block[key] = child
          end
          -- else: explicit null value -> key omitted (see doc comment)
        else
          local v = coerce_scalar(rest)
          if v ~= NULL then
            block[key] = v
          end
        end
      end
    end

    return block, nil
  end

  local result, err = parse_block(0)
  if err then
    return nil, err
  end
  return result, nil
end

return M
