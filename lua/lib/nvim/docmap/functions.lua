---@module 'lib.nvim.docmap.functions'
--- Extracts per-function documentation from a Lua source file via
--- `vim.treesitter`, not `lua-language-server --doc`.
---
--- `--doc` only surfaces symbols reachable through a `@class`/`@alias` type
--- graph — verified against real `doc.json` output (see `luals.lua`'s own
--- header for the same discipline applied there): an ordinary
--- `function M.foo(...)` in a module with no aggregate `@class` declaration
--- for its exports simply does not appear. Retrofitting every module with a
--- redundant aggregate class (duplicating what `---@param`/`---@return`
--- already say above each function) was rejected — two places asserting the
--- same signature is a drift risk, not a shortcut.
---
--- `vim.treesitter` is already bundled with Neovim and already a lib.nvim
--- dependency (`lib.nvim.treesitter`), so this adds nothing new to the "just
--- vim and itself" principle. It is also more robust than a regex/line
--- scanner would have been: a `--` inside a string literal or a multi-line
--- signature are ordinary AST nodes here, not special cases.
---
--- Deliberately narrow, same as `scan.lua`: only the three function shapes
--- that make up this repo's actual public surface are recognized —
--- `function M.foo(...)`, `local function foo(...)`, `M.foo = function(...)`.
--- Anonymous/nested callback functions are not documented units and are not
--- scanned.

local M = {}

-- Two patterns, matched via iter_matches (not iter_captures): the two forms
-- put @fname before or after @fdef in source order depending on which one
-- matched (`M.baz = function(...)` names the target before the function
-- keyword; `function M.bar(...)` does the reverse) — iter_captures' flat,
-- position-ordered stream cannot be regrouped from that alone, verified by
-- a real query run that showed the name arriving before @fdef for the
-- assignment form. iter_matches groups every capture belonging to one match
-- together regardless of source order, which is what correct grouping needs.
local FN_QUERY = vim.treesitter.query.parse("lua", [[
  (function_declaration
    name: (_) @fname
    parameters: (parameters) @params) @fdef

  (assignment_statement
    (variable_list name: (_) @fname)
    (expression_list
      value: (function_definition parameters: (parameters) @params) @fdef))
]])

local COMMENT_QUERY = vim.treesitter.query.parse("lua", "(comment) @comment")

---True when `node` is not nested inside another function's body — a query
---match alone can't tell `local function put(s) ... end` declared at module
---scope from an identically-shaped helper closure nested inside `M.to_json`;
---only walking the ancestor chain can. Verified against a real two-level
---nested `local function` tree: the inner one's parent chain is
---`function_declaration -> block -> function_declaration -> chunk`, so
---hitting a second function-shaped ancestor before `chunk` means "nested."
---@param node TSNode
---@return boolean
local function is_top_level(node)
  local p = node:parent()
  while p do
    local t = p:type()
    if t == "chunk" then
      return true
    end
    if t == "function_declaration" or t == "function_definition" then
      return false
    end
    p = p:parent()
  end
  return false
end

---Split `"type rest..."` into `(type, rest)`, respecting `{}`/`()`/`<>`
---nesting so a type like `table<string, string>` or an anonymous
---`{ a: string, b: integer }` is not cut at the comma/space inside it.
---@param s string
---@return string type_text
---@return string rest
local function split_type(s)
  local depth = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" or c == "(" or c == "<" then
      depth = depth + 1
    elseif c == "}" or c == ")" or c == ">" then
      depth = depth - 1
    elseif c == " " and depth <= 0 then
      return s:sub(1, i - 1), (s:sub(i + 1):gsub("^%s+", ""))
    end
  end
  return s, ""
end

---Parse one already-assembled `---@tag rest` line's `rest` as `param`.
---
---LuaLS accepts the optional-marker `?` on either the name (`name? type`) or
---the type (`name type?`) — this repo's own real usage, verified by grep
---(`---@param node_id string?`, `---@param opts Lib.Docmap.Opts?`), is
---consistently the *type*-suffixed form, not the name-suffixed one the spec
---leads with. Both are recognized so this doesn't silently miss the form
---the codebase actually uses.
---@param rest string
---@return Lib.Docmap.ParamInfo
local function parse_param(rest)
  local name, tail = rest:match("^(%S+)%s*(.*)$")
  name = name or rest
  local optional = false
  if name:sub(-1) == "?" then
    optional = true
    name = name:sub(1, -2)
  end
  local ty, desc = split_type(tail or "")
  if ty:sub(-1) == "?" then
    optional = true
    ty = ty:sub(1, -2)
  end
  return { name = name, type = ty, optional = optional, desc = desc }
end

---@param rest string
---@return Lib.Docmap.ReturnInfo
local function parse_return(rest)
  local ty, tail = split_type(rest)
  local name, desc = tail:match("^([%a_][%w_]*)%s*(.*)$")
  if not name then
    desc = tail
  end
  return { type = ty, name = name, desc = desc or "" }
end

---Strip a comment node's `--`/`---` prefix and one leading space.
---@param line string
---@return string
local function strip_comment(line)
  return (line:gsub("^%-%-%-?%s?", ""))
end

---Parse a function's assembled doc-comment block (top-to-bottom, `---`
---prefix already stripped by the caller) into the tagged fields.
---@param raw_lines string[] Full comment lines, `---` prefix intact.
---@return { summary: string, params: Lib.Docmap.ParamInfo[], returns: Lib.Docmap.ReturnInfo[], generic: string[], deprecated: string?, async: boolean, nodiscard: boolean, see: string[], overload: string[], example: string?, since: string? }
local function parse_doc_block(raw_lines)
  local prose = {}
  local params, returns, generic, see, overload = {}, {}, {}, {}, {}
  local deprecated, since, example
  local async, nodiscard = false, false
  local in_example = false
  local seen_tag = false

  for _, raw in ipairs(raw_lines) do
    local tag, rest = raw:match("^%-%-%-@(%a+)%s*(.*)$")
    if tag then
      seen_tag = true
      in_example = (tag == "example")
      if tag == "param" then
        params[#params + 1] = parse_param(rest)
      elseif tag == "return" then
        returns[#returns + 1] = parse_return(rest)
      elseif tag == "generic" then
        for name in rest:gmatch("[%w_]+") do
          generic[#generic + 1] = name
        end
      elseif tag == "deprecated" then
        deprecated = rest
      elseif tag == "async" then
        async = true
      elseif tag == "nodiscard" then
        nodiscard = true
      elseif tag == "see" then
        for target in rest:gmatch("[^,]+") do
          see[#see + 1] = vim.trim(target)
        end
      elseif tag == "overload" then
        overload[#overload + 1] = rest
      elseif tag == "since" then
        since = rest
      elseif tag == "example" then
        example = rest ~= "" and rest or nil
      end
    elseif in_example then
      local line = strip_comment(raw)
      example = example and (example .. "\n" .. line) or line
    elseif not seen_tag then
      prose[#prose + 1] = strip_comment(raw)
    end
  end

  local summary = require("lib.nvim.docmap.scan").split_summary(table.concat(prose, "\n"))

  return {
    summary = summary,
    params = params,
    returns = returns,
    generic = generic,
    deprecated = deprecated,
    async = async,
    nodiscard = nodiscard,
    see = see,
    overload = overload,
    example = example,
    since = since,
  }
end

---Scan `path` for documented top-level functions.
---@param path string Absolute path to a `.lua` file.
---@return Lib.Docmap.FunctionInfo[]
function M.scan_file(path)
  local fd = io.open(path, "rb")
  if not fd then
    return {}
  end
  local src = fd:read("*a")
  fd:close()

  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "lua")
  if not ok then
    return {}
  end
  local ok_parse, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_parse or not trees or not trees[1] then
    return {}
  end
  local root = trees[1]:root()

  ---@type { row: integer, erow: integer, text: string }[]
  local comments = {}
  for id, node in COMMENT_QUERY:iter_captures(root, src) do
    if COMMENT_QUERY.captures[id] == "comment" then
      local srow, _, erow = node:range()
      local text = vim.treesitter.get_node_text(node, src)
      if text:match("^%-%-%-") then
        comments[#comments + 1] = { row = srow, erow = erow, text = text }
      end
    end
  end

  -- Capture ids are looked up by name rather than assumed positional
  -- (1/2/3): `query.captures[id] -> name` is the documented contract, the
  -- reverse is not guaranteed to match declaration order.
  local id_by_name = {}
  for id, name in ipairs(FN_QUERY.captures) do
    id_by_name[name] = id
  end

  ---@type { name_node: TSNode, params_node: TSNode, def_node: TSNode }[]
  local defs = {}
  for _, match in FN_QUERY:iter_matches(root, src) do
    local name_nodes = match[id_by_name.fname]
    local params_nodes = match[id_by_name.params]
    local def_nodes = match[id_by_name.fdef]
    local name_node = name_nodes and name_nodes[1]
    local params_node = params_nodes and params_nodes[1]
    local def_node = def_nodes and def_nodes[1]
    if name_node and params_node and def_node and is_top_level(def_node) then
      defs[#defs + 1] = { name_node = name_node, params_node = params_node, def_node = def_node }
    end
  end

  table.sort(comments, function(a, b)
    return a.row < b.row
  end)

  ---For a function starting at `frow`, collect the contiguous run of
  ---`---`-comments immediately above it, in original top-to-bottom order.
  ---@param frow integer 0-based row the function definition starts on.
  ---@return string[]
  local function doc_block_above(frow)
    local block = {}
    local want_row = frow - 1
    for i = #comments, 1, -1 do
      local c = comments[i]
      if c.erow == want_row then
        table.insert(block, 1, c.text)
        want_row = c.row - 1
      elseif c.erow < want_row then
        break
      end
    end
    return block
  end

  local out = {}
  for _, def in ipairs(defs) do
    if def.name_node and def.params_node then
      local name = vim.treesitter.get_node_text(def.name_node, src)
      local params_text = vim.treesitter.get_node_text(def.params_node, src)
      local frow = def.def_node:range()
      local raw_lines = doc_block_above(frow)

      -- Undocumented functions (no ---@param/---@return/prose above them)
      -- are real parts of the surface too, just with an empty doc block —
      -- skipping them would make `dead-see-target` and friends blind to
      -- exactly the functions most likely to need a @see fix-up.
      local parsed = parse_doc_block(raw_lines)

      out[#out + 1] = {
        name = name,
        signature = name .. params_text,
        summary = parsed.summary,
        line = frow + 1,
        params = parsed.params,
        returns = parsed.returns,
        generic = parsed.generic,
        deprecated = parsed.deprecated,
        async = parsed.async,
        nodiscard = parsed.nodiscard,
        see = parsed.see,
        overload = parsed.overload,
        example = parsed.example,
        since = parsed.since,
      }
    end
  end

  table.sort(out, function(a, b)
    return a.line < b.line
  end)

  return out
end

return M
