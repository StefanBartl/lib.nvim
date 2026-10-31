---@module 'lib.nvim.json.canonical'
---@brief The canonical JSON encoder of the contract documents: same value, same bytes, on every machine.
---@description
--- Moved here from `tasks_nvim.json` (tasks.nvim@6bc8d99) so that every plugin that speaks a machine contract
--- (`tasks-export/1`, `rules-export/1`) writes the same bytes. Unlike `lib.nvim.json.encode` (a plain encoder) this one
--- is meant for text that is hashed or compared.
---
--- `vim.json.encode` is not good enough for a contract: it writes `{}` as `[]` (an empty Lua table has no type), the
--- order of object keys is whatever `pairs` gives, a float is cut to 16 digits, and `NaN` is an error only some of the
--- time. A document that is hashed (`digest`, `etag`, golden files) needs a writer with rules:
---
---  - object keys sorted by byte value (on plain Lua 5.1 too, where the language's own `<` follows the locale); an
---    object that may be empty is made with `M.object({})` (a mark beside the table; a foreign metatable is not
---    touched, a plain table also gets the mark as its metatable so that `vim.deepcopy` keeps it),
---    an array that may be empty is just `{}` (the default for an empty table) or `M.array({})`; `vim.NIL` is `null`;
---    Neovim's own empty-object marker (`vim.empty_dict()`, and every `{}` that `vim.json.decode` returns) counts as
---    an object, so decode followed by encode keeps `{}` and `[]` apart (a deliberate addition to `tasks_nvim.json`,
---    which did not know the marker)
---  - numbers: a whole number below 2^53 is written without a fraction, any other number with the fewest digits that
---    read back as the same number; `NaN`, `inf` and a whole number of 2^53 or more are an ERROR (a silent loss of
---    digits is the worst answer a contract can give); `-0` is `0`
---  - strings: valid UTF-8 (a bad byte becomes U+FFFD; in an object key before the keys are sorted, and two keys that
---    read the same once repaired are an ERROR), every control byte (the C1 controls U+0080 to U+009F too),
---    `"`, `\`, U+2028, U+2029 and `<` escaped: the text can sit inside a `<script>` block and be printed to a terminal
---    as it is
---  - no whitespace (the form that is hashed); `indent` gives the same document readable (golden files)
---  - a table that is neither a list nor an object (holes, mixed keys) is an error that names the path
---
--- Not its job: what a document contains (the plugin's contract), reading JSON (`vim.json.decode` is fine for that).

require("lib.nvim.json.canonical.@types")

local M = {}

---What `M.object` / `M.array` made of a table: a JSON object or array even when it is empty. Kept beside the table
---(weak keys: a table that goes away takes its mark with it), so a class instance keeps its metatable and its
---`__index`: marking it changes nothing about it but how it is written.
---@type table<table, "object"|"array">
local marks = setmetatable({}, { __mode = "k" })

---The same mark as a metatable, for a plain table (one with no metatable, or with one of these two): `vim.deepcopy`
---copies a metatable but not the weak mark, so a copy of `object({})` is still written `{}`. A table with a foreign
---metatable (a class instance, `vim.empty_dict()`) is never given one; its copy keeps only what its own metatable says.
local OBJECT = { "lib.nvim.json.canonical.object" }
local ARRAY = { "lib.nvim.json.canonical.array" }

---@param t table
---@param kind "object"|"array"
---@return table
local function set_mark(t, kind)
  marks[t] = kind
  local mt = getmetatable(t)
  if mt == nil or mt == OBJECT or mt == ARRAY then
    setmetatable(t, kind == "object" and OBJECT or ARRAY)
  end
  return t
end

---Neovim's own empty-object marker: the metatable of `vim.empty_dict()` and of every `{}` that `vim.json.decode`
---returns. `M.array` still wins over it (a mark is asked first).
local EMPTY_DICT = getmetatable(vim.empty_dict())

local byte = string.byte

---Bytewise `a < b`. Plain Lua 5.1 compares strings with `strcoll` (the collation of the locale: `a` before `B`),
---LuaJIT compares bytes. A canonical text is hashed, so the order must be the same on every machine: never sort the
---keys with the language's own `<`.
---@param a string
---@param b string
---@return boolean
local function bytes_less(a, b)
  local la, lb = #a, #b
  for i = 1, la < lb and la or lb do
    local x, y = byte(a, i), byte(b, i)
    if x ~= y then
      return x < y
    end
  end
  return la < lb
end

---Order for `table.sort` that is the same on every machine (see `bytes_less` above): byte by byte, a shorter string
---before a longer one it is a prefix of. For every list of strings whose order ends up in a hash.
M.bytes_less = bytes_less

---A table that is an OBJECT, empty or not. A foreign metatable stays; a plain table gets the mark as its metatable as
---well (so `vim.deepcopy` keeps it). The last mark wins.
---@generic T: table
---@param t? T
---@return T
function M.object(t)
  return set_mark(t or {}, "object")
end

---A table that is an ARRAY, empty or not (an empty unmarked table is one too). A foreign metatable stays, as above.
---@generic T: table
---@param t? T
---@return T
function M.array(t)
  return set_mark(t or {}, "array")
end

---Tables whose compact text is remembered (`M.memo`). Weak: a table that goes away takes its text with it.
---@type table<table, string|false>
local memo = setmetatable({}, { __mode = "k" })

---Mark a table whose compact text may be reused: the big part of a document (the list of tasks) is written once for
---its digest and once for the answer, and the second time costs nothing. The table must not change afterwards, and
---`indent` ignores the mark (a readable document is rare and small). A memoised table counts its levels like any
---other (a cycle through it fails, and so does nesting deeper than 64) but only while its text is being computed:
---reusing the remembered text does not look at the depth again.
---@generic T: table
---@param t T
---@return T
function M.memo(t)
  memo[t] = false
  return t
end

---Most nesting we accept: a cycle in the data must fail, not hang.
local MAX_DEPTH = 64

---Whole numbers at or above this cannot be told apart from their neighbours in a double.
local MAX_SAFE = 2 ^ 53

---The path of the value being written (`$.a.b[1]`), built only when an error names it.
---@alias Lib.Json.CanonicalWhere fun(depth: integer): string

---@param n number
---@param where Lib.Json.CanonicalWhere
---@param depth integer
---@return string
local function number(n, where, depth)
  if n ~= n or n == math.huge or n == -math.huge then
    error(("json: %s is %s; a contract has no NaN or inf"):format(where(depth), tostring(n)), 0)
  end
  if n == math.floor(n) then
    if math.abs(n) >= MAX_SAFE then
      error(
        ("json: %s is %s, a whole number of 2^53 or more (digits would be lost)"):format(
          where(depth),
          ("%.0f"):format(n)
        ),
        0
      )
    end
    return ("%d"):format(n) -- also turns -0 into 0
  end
  for digits = 15, 17 do
    local text = ("%." .. digits .. "g"):format(n)
    if tonumber(text) == n then
      return text
    end
  end
  return ("%.17g"):format(n)
end

local ESCAPES = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["<"] = "\\u003c",
  ["\127"] = "\\u007f",
}

local FFFD = "\239\191\189"

---The length of the valid UTF-8 sequence that starts at byte `i` of `s` (a byte of 0x80 or more), or 0 when the byte
---starts none: a bad lead byte, a sequence cut off, an overlong form, a surrogate or a value above U+10FFFF.
---@param s string
---@param i integer
---@param n integer  # `#s`
---@return integer
local function sequence(s, i, n)
  local b = byte(s, i)
  local len = 0
  if b >= 0xC2 and b <= 0xDF then
    len = 2
  elseif b >= 0xE0 and b <= 0xEF then
    len = 3
  elseif b >= 0xF0 and b <= 0xF4 then
    len = 4
  end
  if len == 0 or i + len - 1 > n then
    return 0
  end
  for j = 1, len - 1 do
    local c = byte(s, i + j)
    if c < 0x80 or c > 0xBF then
      return 0
    end
  end
  local c1 = byte(s, i + 1)
  -- overlong forms, surrogates and everything above U+10FFFF
  if
    (b == 0xE0 and c1 < 0xA0)
    or (b == 0xED and c1 > 0x9F)
    or (b == 0xF0 and c1 < 0x90)
    or (b == 0xF4 and c1 > 0x8F)
  then
    return 0
  end
  return len
end

---Valid UTF-8 or the same text with every bad byte replaced by U+FFFD. Only the bytes of 0x80 or more are looked at
---one by one (ASCII runs are skipped with one `find`), and a text without a bad byte is handed back as it is: the
---valid stretches between two bad bytes are copied whole, never byte by byte.
---@param s string
---@return string
local function scrub(s)
  local i = s:find("[\128-\255]")
  if not i then
    return s
  end
  local n = #s
  local out, m, from = nil, 0, 1
  while i do
    local len = sequence(s, i, n)
    if len > 0 then
      i = i + len
    else
      out = out or {}
      out[m + 1] = s:sub(from, i - 1)
      out[m + 2] = FFFD
      m = m + 2
      i = i + 1
      from = i
    end
    i = s:find("[\128-\255]", i)
  end
  if not out then
    return s
  end
  out[m + 1] = s:sub(from)
  return table.concat(out)
end

---The text as `encode` writes it, before the escapes: valid UTF-8, every bad byte (also an overlong form, a surrogate
---and a value above U+10FFFF) replaced by U+FFFD. For a caller that has to judge or show a text the way the document
---will hold it: `scrub_utf8(s) ~= s` says that `s` is not valid UTF-8.
M.scrub_utf8 = scrub

---@param s string
---@return string
local function string_(s)
  -- Most strings (ids, keys, plain words) have nothing to escape: one scan instead of four substitutions.
  if not s:find('[%c"\\<\127\128-\255]') then
    return '"' .. s .. '"'
  end
  s = scrub(s)
  -- each substitution only where it has something to do: a long non-ASCII text (a task body) mostly has none
  if s:find('[%c"\\<\127]') then
    s = s:gsub('[%c"\\<\127]', function(c)
      return ESCAPES[c] or ("\\u%04x"):format(c:byte())
    end)
  end
  if s:find("\226\128[\168\169]") then
    s = s:gsub("\226\128[\168\169]", function(c)
      return c:byte(3) == 168 and "\\u2028" or "\\u2029"
    end)
  end
  -- the 8-bit C1 controls (CSI is U+009B) are two bytes in UTF-8; a terminal may act on them
  if s:find("\194[\128-\159]") then
    s = s:gsub("\194[\128-\159]", function(c)
      return ("\\u%04x"):format(c:byte(2))
    end)
  end
  return '"' .. s .. '"'
end

---Most texts of escaped object keys that are remembered (`key_text`). The keys of a document are few and repeat in
---every entry; a document with many distinct keys only fills the cache, which then starts over.
local KEY_CACHE_MAX = 1024

---Escaped object key followed by its `:`, per key. Strings are values in Lua: a weak table would never drop them,
---hence the cap instead.
---@type table<string, string>
local key_text, key_count = {}, 0

---@param k string
---@return string  # `"k":`, escaped as any string
local function key_(k)
  local text = key_text[k]
  if not text then
    text = string_(k) .. ":"
    if key_count >= KEY_CACHE_MAX then
      key_text, key_count = {}, 0
    end
    key_text[k] = text
    key_count = key_count + 1
  end
  return text
end

---Object, list or error: what a table is, and the keys of an object in the order they are written (one pass over the
---table; a list answers its length instead of a list of its indices).
---@param t table
---@param where Lib.Json.CanonicalWhere
---@param depth integer
---@return "object"|"array"
---@return string[]|integer keys  # the sorted keys of an object as they are written, the length of a list
---@return table<string, string>|nil source  # written key -> key of `t`, for the keys that are not valid UTF-8
local function shape(t, where, depth)
  local mt = getmetatable(t)
  local mark = marks[t] or (mt == OBJECT and "object") or (mt == ARRAY and "array") or nil
  local count, max, strings = 0, 0, 0
  local keys, source = {}, nil
  for k in pairs(t) do
    count = count + 1
    if type(k) == "number" and k >= 1 and k == math.floor(k) then
      if k > max then
        max = k
      end
    elseif type(k) == "string" then
      strings = strings + 1
      -- A key that is not valid UTF-8 is written repaired (U+FFFD): it is sorted under that name, and two keys that
      -- end up with the same name are an error, since a decoder keeps only one of their values.
      if k:find("[\128-\255]") then
        local fixed = scrub(k)
        if fixed ~= k then
          source = source or {}
          -- rawget: a metatable is kept now (a class instance), and its __index must not invent a second key
          if source[fixed] ~= nil or rawget(t, fixed) ~= nil then
            error(
              ("json: %s has two keys that both read %s once invalid UTF-8 is replaced"):format(
                where(depth),
                string_(fixed)
              ),
              0
            )
          end
          source[fixed] = k
          k = fixed
        end
      end
      keys[strings] = k
    else
      error(("json: %s has a key of type %s"):format(where(depth), type(k)), 0)
    end
  end
  if mark == "object" or (mark ~= "array" and (mt == EMPTY_DICT or strings > 0)) then
    if count ~= strings then
      error(("json: %s mixes list and object keys"):format(where(depth)), 0)
    end
    table.sort(keys, bytes_less)
    return "object", keys, source
  end
  if strings > 0 or max ~= count then
    error(
      ("json: %s is not a list (holes or a string key); mark it with json.object if it is an object"):format(
        where(depth)
      ),
      0
    )
  end
  return "array", count
end

---@param value any
---@param indent? integer
---@param path0 string
---@param bypass? boolean  # The root itself is not looked up in the memo (it is being computed).
---@param depth0? integer  # The level of the root: a memoised table is rendered from its own level, not from 0.
---@return string
local function render(value, indent, path0, bypass, depth0)
  depth0 = depth0 or 0
  local out, n = {}, 0
  -- The key that leads to each level below the root (`steps[depth]`). The path of a value is only needed by an
  -- error; building it as a string for every value cost a fifth of the whole encode.
  local steps = {}
  ---@type Lib.Json.CanonicalWhere
  local function where(depth)
    local parts = { path0 }
    for d = depth0 + 1, depth do
      local k = steps[d]
      parts[#parts + 1] = type(k) == "number" and ("[" .. k .. "]") or ("." .. k)
    end
    return table.concat(parts)
  end
  local colon = indent and " " or nil
  local function put(v, depth)
    local ty = type(v)
    if v == nil or v == vim.NIL then
      n = n + 1
      out[n] = "null"
    elseif ty == "boolean" then
      n = n + 1
      out[n] = v and "true" or "false"
    elseif ty == "number" then
      n = n + 1
      out[n] = number(v, where, depth)
    elseif ty == "string" then
      n = n + 1
      out[n] = string_(v)
    elseif ty == "table" then
      if depth > MAX_DEPTH then
        error(
          ("json: %s is nested deeper than %d levels (a cycle?)"):format(where(depth), MAX_DEPTH),
          0
        )
      end
      if not indent and memo[v] ~= nil and not (bypass and depth == depth0) then
        local text = memo[v] or render(v, nil, where(depth), true, depth)
        memo[v] = text
        n = n + 1
        out[n] = text
        return
      end
      local kind, keys, source = shape(v, where, depth)
      local inner = depth + 1
      local pad = indent and ("\n" .. string.rep(" ", indent * inner)) or nil
      if kind == "object" then
        ---@cast keys string[]
        if #keys == 0 then
          n = n + 1
          out[n] = "{}"
          return
        end
        n = n + 1
        out[n] = "{"
        for i = 1, #keys do
          local k = keys[i]
          if i > 1 then
            n = n + 1
            out[n] = ","
          end
          if pad then
            n = n + 1
            out[n] = pad
          end
          n = n + 1
          out[n] = key_(k)
          if colon then
            n = n + 1
            out[n] = colon
          end
          steps[inner] = k
          put(v[source and source[k] or k], inner)
        end
      else
        ---@cast keys integer
        if keys == 0 then
          n = n + 1
          out[n] = "[]"
          return
        end
        n = n + 1
        out[n] = "["
        for i = 1, keys do
          if i > 1 then
            n = n + 1
            out[n] = ","
          end
          if pad then
            n = n + 1
            out[n] = pad
          end
          steps[inner] = i
          put(v[i], inner)
        end
      end
      n = n + 1
      out[n] = (indent and ("\n" .. string.rep(" ", indent * depth)) or "")
        .. (kind == "object" and "}" or "]")
    else
      error(("json: %s is a %s, which JSON cannot hold"):format(where(depth), ty), 0)
    end
  end
  put(value, depth0)
  return table.concat(out)
end

---@param value any
---@param opts? Lib.Json.CanonicalOpts
---@return string
function M.encode(value, opts)
  return render(value, opts and opts.indent, "$")
end

---@type Lib.Json.Canonical
return M
