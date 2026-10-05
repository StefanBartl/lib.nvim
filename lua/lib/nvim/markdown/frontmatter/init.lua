---@module 'lib.nvim.markdown.frontmatter'
---@brief Read and surgically update the flat-YAML frontmatter block of a Markdown text or file.
---@description
--- Understands exactly one shape: a leading block between two `---` lines
--- whose lines are `key: value` pairs. Values are a plain or quoted string,
--- a boolean, or an inline list `[a, b]`; there is no nesting and no
--- multi-line value. A cheap, predictable reading beats a general one: what
--- is not understood is never guessed at, it is kept verbatim.
---
--- Key responsibilities:
---  - `parse`: block detection (BOM, LF/CRLF), `meta` + `order`, `warnings`
---  - `patch` / `update_text` / `update`: change only the touched keys; every
---    other byte (unknown keys, comments, blank lines, the body, the line
---    endings, the BOM) comes back identical
---  - never throw on malformed input: `nil, err`, or a parse carrying warnings
---
--- Not its job: general YAML (anchors, maps, block scalars -- a key with such
--- a value is listed in `parsed.opaque` and refused for writing, never
--- rewritten), and any notification or UI (callers decide how loud to be).
---@see lib.nvim.fs.json

require("lib.nvim.markdown.frontmatter.@types")

local fs_read = require("lib.nvim.fs.read")
local mutate = require("lib.nvim.cross.fs.mutate")

local uv = vim.uv or vim.loop

local M = {}

---Patch value that deletes a key. It is `vim.NIL`, so a patch decoded from
---JSON (`{"prio": null}`) removes too. `false` is a boolean, never a removal.
---@type userdata
M.REMOVE = vim.NIL

local REMOVE = M.REMOVE

local BOM = "\239\187\191"

-- ─────────────────────────────────────────────────────────────────────────────
-- Reading
-- ─────────────────────────────────────────────────────────────────────────────

---Index of the last byte of `s` that is not whitespace (0 when there is none).
---Walks back from the end, so it is linear in the trailing run. The obvious
---`s:gsub("%s+$", "")` and `s:match("^%s*(.-)%s*$")` retry the whole rest of a
---whitespace run from every byte inside it: 40 000 spaces cost about 6 s, 160 000
---about 100 s, on one frontmatter line (SEC-32).
---@param s string
---@return integer
local function last_non_space(s)
  local i = #s
  while i > 0 and s:find("^%s", i) do
    i = i - 1
  end
  return i
end

---@param s string
---@return string
local function rtrim(s)
  return s:sub(1, last_non_space(s))
end

---@param s string
---@return string
local function trim(s)
  local first = s:find("%S")
  if not first then
    return ""
  end
  return s:sub(first, last_non_space(s))
end

---Start of the first whitespace run that is directly followed by `#` (a YAML
---comment), or nil. The same match as `s:find("%s+#")`, without that pattern's
---quadratic retry inside a long whitespace run.
---@param s string
---@return integer|nil
local function find_comment_start(s)
  local init = 1
  while true do
    local hash = s:find("#", init, true)
    if not hash then
      return nil
    end
    if hash > 1 and s:find("^%s", hash - 1) then
      local start = hash - 1
      while start > 1 and s:find("^%s", start - 1) do
        start = start - 1
      end
      return start
    end
    init = hash + 1
  end
end

---Split one line off `text` at `pos`. The line ending is returned separately
---(`"\n"`, `"\r\n"`, or `""` at end of file) so it can be written back as read.
---@param text string
---@param pos integer
---@return string line
---@return string eol
---@return integer next_pos
local function next_line(text, pos)
  local nl = text:find("\n", pos, true)
  if not nl then
    return text:sub(pos), "", #text + 1
  end
  local line = text:sub(pos, nl - 1)
  if line:sub(-1) == "\r" then
    return line:sub(1, -2), "\r\n", nl + 1
  end
  return line, "\n", nl + 1
end

---@param line string
---@return boolean
local function is_delimiter(line)
  return line:match("^%-%-%-[ \t]*$") ~= nil
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

---Scan a quoted scalar whose opening quote is at `s[i]`.
---@param s string
---@param i integer
---@return string|nil content  nil when the quote never closes
---@return integer|nil next_index  index just after the closing quote
local function scan_quoted(s, i)
  local quote = s:sub(i, i)
  local out = {}
  local j = i + 1
  local len = #s
  while j <= len do
    local c = s:sub(j, j)
    if quote == '"' and c == "\\" then
      local nxt = s:sub(j + 1, j + 1)
      if nxt == "" then
        return nil
      end
      -- An escape this module does not know stays as written.
      out[#out + 1] = ESCAPES[nxt] or ("\\" .. nxt)
      j = j + 2
    elseif c == quote then
      if quote == "'" and s:sub(j + 1, j + 1) == "'" then
        out[#out + 1] = "'"
        j = j + 2
      else
        return table.concat(out), j + 1
      end
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
  return nil
end

---What may follow a value: nothing, or whitespace plus a `#` comment.
---@param rest string
---@return string|nil comment  the comment with its leading whitespace
---@return boolean ok
local function scan_tail(rest)
  if rest:match("^%s*$") then
    return nil, true
  end
  if rest:match("^%s+#") then
    return rtrim(rest), true
  end
  return nil, false
end

---@param v string  starts with `[`
---@return string[]|nil items
---@return string|nil comment
---@return string|nil err
local function parse_flow_list(v)
  local items = {}
  local len = #v
  local i = 2
  while true do
    i = v:find("%S", i) or (len + 1)
    local c = v:sub(i, i)
    if c == "" then
      return nil, nil, "unterminated list"
    elseif c == "]" then
      i = i + 1
      break
    elseif c == "," then
      i = i + 1
    elseif c == '"' or c == "'" then
      local content, j = scan_quoted(v, i)
      if not content then
        return nil, nil, "unterminated quoted list item"
      end
      items[#items + 1] = content
      local k = v:find("%S", j) or (len + 1)
      local d = v:sub(k, k)
      if d ~= "," and d ~= "]" then
        return nil, nil, "unexpected text after a quoted list item"
      end
      i = k
    else
      local j = v:find("[,%]]", i)
      local item = trim(v:sub(i, (j or (len + 1)) - 1))
      local first = item:sub(1, 1)
      if first == "[" or first == "{" then
        return nil, nil, "nested list items are not supported"
      end
      items[#items + 1] = item
      i = j or (len + 1)
    end
  end
  local comment, ok = scan_tail(v:sub(i))
  if not ok then
    return nil, nil, "unexpected text after the list"
  end
  return items, comment
end

---Does plain text read as a number in `numbers` mode?
---@param v string
---@return boolean
local function looks_numeric(v)
  return v:match("^[+-]?%d+%.?%d*$") ~= nil or v:match("^[+-]?%.%d+$") ~= nil
end

---Parse what follows `key:` on a line.
---@param rest string  text after the colon, empty or starting with whitespace
---@param numbers boolean
---@return any value
---@return string|nil comment
---@return string|nil err  set when the shape is not understood (value is then meaningless)
local function parse_value(rest, numbers)
  local v = rest:match("^%s*(.*)$")
  if v == "" then
    return "", nil
  end
  local first = v:sub(1, 1)
  if first == "#" then
    return "", rtrim(rest)
  elseif first == '"' or first == "'" then
    local content, j = scan_quoted(v, 1)
    if not content then
      return nil, nil, "unterminated quoted value"
    end
    local comment, ok = scan_tail(v:sub(j))
    if not ok then
      return nil, nil, "unexpected text after the quoted value"
    end
    return content, comment
  elseif first == "[" then
    local items, comment, err = parse_flow_list(v)
    if not items then
      return nil, nil, err
    end
    return items, comment
  elseif first:find("[{|>&*!]") then
    return nil, nil, "unsupported value shape"
  end

  local comment
  local s = find_comment_start(v)
  if s then
    comment = rtrim(v:sub(s))
    v = v:sub(1, s - 1)
  end
  v = rtrim(v)
  if v == "true" then
    return true, comment
  elseif v == "false" then
    return false, comment
  end
  if numbers and looks_numeric(v) then
    return tonumber(v), comment
  end
  return v, comment
end

---@param parsed Lib.Markdown.Frontmatter.Parsed
local function refresh_raw_lines(parsed)
  local raw = {}
  for i, e in ipairs(parsed.entries) do
    raw[i] = e.raw
  end
  parsed.raw_lines = raw
end

---@param text any
---@param opts? Lib.Markdown.Frontmatter.ParseOpts
---@return Lib.Markdown.Frontmatter.Parsed|nil parsed
---@return string|nil err  only for non-string input; malformed text parses with warnings
function M.parse(text, opts)
  if type(text) ~= "string" then
    return nil, "text must be a string"
  end
  local numbers = (opts and opts.numbers) == true

  ---@type Lib.Markdown.Frontmatter.Parsed
  local parsed = {
    has_block = false,
    unterminated = false,
    bom = "",
    eol = "\n",
    meta = {},
    order = {},
    body = text,
    warnings = {},
    raw_lines = {},
    entries = {},
    opaque = {},
    numbers = numbers,
    prose = false,
    by_key = {},
  }

  local pos = 1
  if text:sub(1, 3) == BOM then
    parsed.bom = BOM
    pos = 4
  end

  local first, first_eol, p = next_line(text, pos)
  if first_eol ~= "" then
    parsed.eol = first_eol
  end
  if first_eol == "" or not is_delimiter(first) then
    parsed.body = text:sub(pos)
    return parsed
  end

  local entries = {}
  local warnings = {}
  local last_kv ---@type Lib.Markdown.Frontmatter.Entry|nil
  local keyed, stray = 0, 0
  local closed = false
  local lineno = 1
  local len = #text
  while p <= len do
    local line, eol, np = next_line(text, p)
    lineno = lineno + 1
    p = np
    if is_delimiter(line) then
      parsed.close, parsed.close_eol = line, eol
      closed = true
      break
    end

    ---@type Lib.Markdown.Frontmatter.Entry
    local entry = { raw = line, eol = eol, line = lineno }
    local key, rest = line:match("^([%w_][%w_%.%-]*)[ \t]*:(.*)$")
    if key and (rest == "" or rest:match("^[ \t]")) then
      local value, comment, err = parse_value(rest, numbers)
      entry.key = key
      if err then
        entry.opaque = err
        warnings[#warnings + 1] = ("line %d: key '%s': %s, kept verbatim"):format(lineno, key, err)
      else
        entry.value, entry.comment = value, comment
      end
      last_kv = entry
      keyed = keyed + 1
    elseif line:match("^%s*$") or line:match("^%s*#") then
      last_kv = nil
    elseif last_kv and (line:match("^[ \t]") or line:match("^%-[ \t]") or line == "-") then
      -- Continuation of the previous key: a nested map, a block list or a
      -- multi-line scalar. None of that is read, and none of it is rewritten.
      if not last_kv.opaque then
        last_kv.opaque = "nested or multi-line value"
        warnings[#warnings + 1] = ("line %d: key '%s' has a nested or multi-line value, kept verbatim"):format(
          last_kv.line,
          last_kv.key
        )
      end
    else
      last_kv = nil
      stray = stray + 1
      warnings[#warnings + 1] = ("line %d: not a `key: value` line, kept verbatim"):format(lineno)
    end
    entries[#entries + 1] = entry
  end

  if not closed then
    parsed.unterminated = true
    parsed.body = text:sub(pos)
    parsed.warnings = { "frontmatter block is not closed by a second `---` line" }
    return parsed
  end

  parsed.has_block = true
  -- Foreign lines and not one `key: value` line: prose between two `---`
  -- lines (a horizontal rule pair), not frontmatter. Never patched.
  parsed.prose = keyed == 0 and stray > 0
  parsed.open, parsed.open_eol = first, first_eol
  parsed.body = text:sub(p)
  parsed.entries = entries
  parsed.warnings = warnings

  -- Index the entries. A key written twice: the last one is the effective
  -- value (as in most YAML readers), reported once in `order`.
  for _, e in ipairs(entries) do
    if e.key and e.opaque then
      parsed.opaque[e.key] = e.opaque
    end
  end
  for _, e in ipairs(entries) do
    if e.key and not parsed.opaque[e.key] then
      if parsed.by_key[e.key] then
        parsed.warnings[#parsed.warnings + 1] = ("line %d: key '%s' appears more than once, the last one wins"):format(
          e.line,
          e.key
        )
      else
        parsed.order[#parsed.order + 1] = e.key
      end
      parsed.by_key[e.key] = e
      parsed.meta[e.key] = e.value
    end
  end
  refresh_raw_lines(parsed)
  return parsed
end

---The value of `key`, or `default` when the key is absent (or unreadable, see
---`parsed.opaque`). A stored `false` is returned as `false`.
---@param parsed Lib.Markdown.Frontmatter.Parsed
---@param key string
---@param default? any
---@return any
function M.get(parsed, key, default)
  local v = parsed.meta[key]
  if v == nil then
    return default
  end
  return v
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Writing values
-- ─────────────────────────────────────────────────────────────────────────────

local RESERVED_WORDS = { ["true"] = true, ["false"] = true, ["null"] = true, ["~"] = true }

---Would a string written bare be read back as something else, or not at all?
---Deliberately stricter than this module's reader: the file should also stay
---a string for a full YAML parser (GitHub, other tools).
---@param s string
---@return boolean
local function needs_quotes(s)
  if s == "" or s:find("^%s") or s:find("%s$") or s:find("%c") then
    return true
  end
  local first = s:sub(1, 1)
  if first:find("[%[%]{}#&*!|>'\"%%@`,]") then
    return true
  end
  if first == "-" or first == "?" or first == ":" then
    if #s == 1 or s:sub(2, 2):find("%s") then
      return true
    end
  end
  if s:find(": ", 1, true) or s:sub(-1) == ":" or s:find("%s#") then
    return true
  end
  return RESERVED_WORDS[s:lower()] == true
end

---@param s string
---@return string|nil quoted
---@return string|nil err
local function quote_double(s)
  local bad
  local out = s:gsub('[%c"\\]', function(c)
    if c == '"' then
      return '\\"'
    elseif c == "\\" then
      return "\\\\"
    elseif c == "\n" then
      return "\\n"
    elseif c == "\t" then
      return "\\t"
    elseif c == "\r" then
      return "\\r"
    end
    bad = c
    return c
  end)
  if bad then
    return nil, "string contains a control character that cannot be written"
  end
  return '"' .. out .. '"'
end

---@param s string
---@param in_list boolean
---@param numbers? boolean  number mode: a scalar that reads as a number must be quoted to stay a string
---@return string|nil rendered
---@return string|nil err
local function render_string(s, in_list, numbers)
  if
    needs_quotes(s)
    or (in_list and s:find("[,%[%]{}]"))
    or (numbers and not in_list and looks_numeric(s))
  then
    return quote_double(s)
  end
  return s
end

---@param n number
---@return string|nil rendered
---@return string|nil err
local function format_number(n)
  if n ~= n or n == math.huge or n == -math.huge then
    return nil, "number is not finite"
  end
  if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
    return string.format("%d", n)
  end
  return (string.format("%.14g", n))
end

---Validate one patch value and work out both its line form and the value a
---re-read of that line would yield (`normalized`), so `meta` never drifts
---from what the file now says.
---@param value any
---@param numbers boolean  the parse mode: whether number-looking text reads as a number
---@return any normalized
---@return string|nil rendered
---@return string|nil err
local function prepare_value(value, numbers)
  local t = type(value)
  if t == "string" then
    local rendered, err = render_string(value, false, numbers)
    return value, rendered, err
  elseif t == "boolean" then
    return value, tostring(value)
  elseif t == "number" then
    local rendered, err = format_number(value)
    if not rendered then
      return nil, nil, err
    end
    return (numbers and value or rendered), rendered
  elseif t == "table" then
    local n = #value
    for k in pairs(value) do
      if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
        return nil, nil, "a table value must be a plain list"
      end
    end
    local items, parts = {}, {}
    for i = 1, n do
      local item = value[i]
      local it = type(item)
      if it == "number" then
        local s, err = format_number(item)
        if not s then
          return nil, nil, err
        end
        item = s
      elseif it == "boolean" then
        item = tostring(item)
      elseif it ~= "string" then
        return nil, nil, "list items must be strings, numbers or booleans"
      end
      local rendered, err = render_string(item, true)
      if not rendered then
        return nil, nil, err
      end
      items[i], parts[i] = item, rendered
    end
    return items, "[" .. table.concat(parts, ", ") .. "]"
  end
  return nil, nil, ("unsupported value type '%s'"):format(t)
end

---@param a any
---@param b any
---@return boolean
local function same_value(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Patching
-- ─────────────────────────────────────────────────────────────────────────────

---@param key any
---@return boolean
local function valid_key(key)
  return type(key) == "string" and key:match("^[%w_][%w_%.%-]*$") ~= nil
end

---A patch is a map (applied in sorted key order) or a list of `{ key, value }`
---pairs (applied in the given order).
---@param patch any
---@return { key: string, value: any }[]|nil ops
---@return string|nil err
local function normalize_patch(patch)
  if type(patch) ~= "table" then
    return nil, "patch must be a table"
  end
  local ops = {}
  if patch[1] ~= nil then
    for k in pairs(patch) do
      if type(k) ~= "number" then
        return nil, "patch mixes list and map entries"
      end
    end
    for i, pair in ipairs(patch) do
      if type(pair) ~= "table" or type(pair[1]) ~= "string" then
        return nil, ("patch entry %d must be { key, value }"):format(i)
      end
      if pair[2] == nil then
        return nil,
          ("patch entry %d: value is nil, use frontmatter.REMOVE to delete a key"):format(i)
      end
      ops[#ops + 1] = { key = pair[1], value = pair[2] }
    end
    return ops
  end
  local keys = {}
  for k in pairs(patch) do
    if type(k) ~= "string" then
      return nil, "patch keys must be strings"
    end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    ops[#ops + 1] = { key = k, value = patch[k] }
  end
  return ops
end

---@param parsed Lib.Markdown.Frontmatter.Parsed
---@param key string
local function remove_key(parsed, key)
  if not parsed.by_key[key] then
    return
  end
  local kept = {}
  for _, e in ipairs(parsed.entries) do
    if e.key ~= key then
      kept[#kept + 1] = e
    end
  end
  parsed.entries = kept
  parsed.by_key[key] = nil
  parsed.meta[key] = nil
  for i, k in ipairs(parsed.order) do
    if k == key then
      table.remove(parsed.order, i)
      break
    end
  end
end

---@param parsed Lib.Markdown.Frontmatter.Parsed
local function open_block(parsed)
  parsed.has_block = true
  parsed.open, parsed.open_eol = "---", parsed.eol
  parsed.close, parsed.close_eol = "---", parsed.eol
end

---Apply `patch` to `parsed` in place. All or nothing: a patch with one bad
---entry changes nothing.
---
---Semantics per key: a value sets it (an existing line is rewritten in place,
---a new key is appended before the closing `---`, an equal value touches
---nothing); `frontmatter.REMOVE` deletes every line of that key (absent key:
---nothing happens).
---@param parsed Lib.Markdown.Frontmatter.Parsed
---@param patch Lib.Markdown.Frontmatter.Patch
---@param opts? Lib.Markdown.Frontmatter.PatchOpts
---@return boolean ok
---@return string|nil err
function M.patch(parsed, patch, opts)
  if type(parsed) ~= "table" or type(parsed.entries) ~= "table" then
    return false, "not a parsed frontmatter table"
  end
  local ops, nerr = normalize_patch(patch)
  if not ops then
    return false, nerr
  end

  if parsed.prose then
    return false, "the `---` block holds prose, not `key: value` lines, refusing to patch it"
  end

  local any_set = false
  for _, op in ipairs(ops) do
    if not valid_key(op.key) then
      return false, ("invalid key '%s'"):format(tostring(op.key))
    end
    local reason = parsed.opaque[op.key]
    if reason then
      return false,
        ("key '%s' has a value this module does not rewrite (%s)"):format(op.key, reason)
    end
    if op.value ~= REMOVE then
      any_set = true
      local normalized, rendered, err = prepare_value(op.value, parsed.numbers)
      if not rendered then
        return false, ("key '%s': %s"):format(op.key, err)
      end
      op.normalized, op.rendered = normalized, rendered
    end
  end

  if not parsed.has_block then
    if parsed.unterminated then
      return false, "frontmatter block is not closed, refusing to add a second one"
    end
    if not any_set then
      return true
    end
    if not (opts and opts.create) then
      return false, "no frontmatter block (pass create = true to add one)"
    end
    open_block(parsed)
  end

  for _, op in ipairs(ops) do
    local key = op.key
    if op.value == REMOVE then
      remove_key(parsed, key)
    else
      local entry = parsed.by_key[key]
      if entry then
        if not same_value(entry.value, op.normalized) then
          entry.raw = key .. ": " .. op.rendered .. (entry.comment or "")
          entry.value = op.normalized
          parsed.meta[key] = op.normalized
        end
      else
        ---@type Lib.Markdown.Frontmatter.Entry
        local new = {
          raw = key .. ": " .. op.rendered,
          eol = parsed.eol,
          key = key,
          value = op.normalized,
        }
        parsed.entries[#parsed.entries + 1] = new
        parsed.by_key[key] = new
        parsed.meta[key] = op.normalized
        parsed.order[#parsed.order + 1] = key
      end
    end
  end
  refresh_raw_lines(parsed)
  return true
end

---Set a single key. Sugar for `patch(parsed, { [key] = value }, opts)`.
---@param parsed Lib.Markdown.Frontmatter.Parsed
---@param key string
---@param value any  a value, or `frontmatter.REMOVE`
---@param opts? Lib.Markdown.Frontmatter.PatchOpts
---@return boolean ok
---@return string|nil err
function M.set(parsed, key, value, opts)
  return M.patch(parsed, { { key, value } }, opts)
end

---The text a parse describes. For an untouched parse this is the input,
---byte for byte.
---@param parsed Lib.Markdown.Frontmatter.Parsed
---@return string
function M.serialize(parsed)
  if not parsed.has_block then
    return parsed.bom .. parsed.body
  end
  local out = { parsed.bom, parsed.open, parsed.open_eol }
  for _, e in ipairs(parsed.entries) do
    out[#out + 1] = e.raw
    out[#out + 1] = e.eol
  end
  out[#out + 1] = parsed.close
  out[#out + 1] = parsed.close_eol
  out[#out + 1] = parsed.body
  return table.concat(out)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Text and file helpers
-- ─────────────────────────────────────────────────────────────────────────────

---Return `text` with `patch` applied; only the touched keys differ.
---@param text string
---@param patch Lib.Markdown.Frontmatter.Patch
---@param opts? Lib.Markdown.Frontmatter.PatchOpts
---@return string|nil new_text
---@return string|nil err
function M.update_text(text, patch, opts)
  local parsed, perr = M.parse(text, opts)
  if not parsed then
    return nil, perr
  end
  local ok, err = M.patch(parsed, patch, opts)
  if not ok then
    return nil, err
  end
  return M.serialize(parsed)
end

---Put a frontmatter block on a text that has none (an empty `meta` adds an
---empty block). Fails when the text already starts with one.
---@param text string
---@param meta? Lib.Markdown.Frontmatter.Patch
---@param opts? Lib.Markdown.Frontmatter.PatchOpts
---@return string|nil new_text
---@return string|nil err
function M.add_block(text, meta, opts)
  local parsed, perr = M.parse(text, opts)
  if not parsed then
    return nil, perr
  end
  if parsed.has_block then
    return nil, "text already has a frontmatter block"
  end
  if parsed.unterminated then
    return nil, "frontmatter block is not closed, refusing to add a second one"
  end
  open_block(parsed)
  local ok, err = M.patch(parsed, meta or {}, opts)
  if not ok then
    return nil, err
  end
  return M.serialize(parsed)
end

---Read and parse a file.
---@param path string
---@param opts? Lib.Markdown.Frontmatter.ParseOpts
---@return Lib.Markdown.Frontmatter.Parsed|nil parsed
---@return string|nil err
function M.read(path, opts)
  local content, err = fs_read(path)
  if not content then
    return nil, err
  end
  return M.parse(content, opts)
end

---Byte-exact atomic write: a sibling temp file, then a rename over the target.
---(`fs.write.to_file` is not used: it appends a newline to content that lacks
---one, which would change a file whose body does not end in one.)
---@param path string
---@param content string
---@return boolean ok
---@return string|nil err
local function write_atomic(path, content)
  local target = uv.fs_realpath(path) or path
  -- Unique per process and call: two writers must not share one temp file.
  local tmp = ("%s.frontmatter.%d.%d.tmp"):format(target, uv.os_getpid(), uv.hrtime())
  local f, open_err = io.open(tmp, "wb")
  if not f then
    return false, "open failed: " .. tostring(open_err)
  end
  local ok_write, write_err = f:write(content)
  local ok_close, close_err = f:close()
  if not ok_write or not ok_close then
    pcall(os.remove, tmp)
    return false, "write failed: " .. tostring(write_err or close_err)
  end
  local st = uv.fs_stat(target)
  if st then
    pcall(uv.fs_chmod, tmp, st.mode % 4096)
  end
  local ok_rename, rename_err = mutate.rename_file(tmp, target)
  if not ok_rename then
    pcall(os.remove, tmp)
    return false, "rename failed: " .. tostring(rename_err)
  end
  return true
end

---Apply `patch` to the file at `path`. Nothing is written when the patch
---changes nothing (no mtime churn, no file watcher noise).
---@param path string
---@param patch Lib.Markdown.Frontmatter.Patch
---@param opts? Lib.Markdown.Frontmatter.PatchOpts
---@return boolean ok
---@return string|nil err
function M.update(path, patch, opts)
  local content, rerr = fs_read(path)
  if not content then
    return false, rerr
  end
  local new_text, err = M.update_text(content, patch, opts)
  if not new_text then
    return false, err
  end
  if new_text == content then
    return true
  end
  return write_atomic(path, new_text)
end

---@type Lib.Markdown.Frontmatter
return M
