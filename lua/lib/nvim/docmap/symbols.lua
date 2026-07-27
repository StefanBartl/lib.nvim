---@module 'lib.nvim.docmap.symbols'
--- Module-scope tables, constants and bindings — the part of a module's
--- surface that is not a function and was, until now, invisible in the map.
---
--- `docmap.functions` answers "what can I call"; this answers the rest of
--- "what is in here": the lookup tables a module dispatches through, the
--- constants that encode its thresholds, the singletons it holds. Reading a
--- module's source, those are usually the first things you look for and the
--- last things any generated documentation shows.
---
--- Runs on the tree `docmap.functions` already parsed — no extra read, no
--- extra parse. Top level only, anchored on `(chunk …)` in the query rather
--- than by walking ancestors: a `local seen = {}` inside a function body is an
--- implementation detail, exactly as a nested `local function` is.
---
--- Two shapes are deliberately *not* reported, because another stage already
--- owns them and reporting them twice would be two places to keep in sync:
---
---   local fs = require("…")   -> `docmap.deps` (it is a dependency)
---   M.foo = function(…)       -> `docmap.functions` (it is a function)

local M = {}

-- Both top-level assignment shapes. `local x = …` nests an assignment inside
-- a variable_declaration; `M.x = …` is a bare assignment_statement. Anchoring
-- each on `chunk` is what restricts this to module scope.
local SYMBOL_QUERY = vim.treesitter.query.parse(
  "lua",
  [[
  (chunk
    (variable_declaration
      (assignment_statement
        (variable_list name: (_) @name)
        (expression_list value: (_) @value))))

  (chunk
    (assignment_statement
      (variable_list name: (_) @name)
      (expression_list value: (_) @value)))
]]
)

---Collapse a value expression to one short line for display.
---@param text string
---@return string
local function condense(text)
  local flat = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #flat > 48 then
    flat = flat:sub(1, 47) .. "…"
  end
  return flat
end

---Number of `field` children of a table constructor — "12 fields" is the one
---thing worth saying about a table without reproducing it.
---@param node TSNode
---@return integer
local function count_fields(node)
  local n = 0
  for i = 0, node:named_child_count() - 1 do
    if node:named_child(i):type() == "field" then
      n = n + 1
    end
  end
  return n
end

---Classify a module-scope binding by what it is bound to.
---@param value TSNode
---@param text string Source text of the value expression.
---@return Lib.Docmap.SymbolKind?
---@return string detail
local function classify(value, text)
  local ty = value:type()

  if ty == "function_definition" then
    return nil, ""
  end
  -- A require binding is a dependency, and `docmap.deps` already models it —
  -- including the alias, which is what makes call resolution work.
  if text:match("^require%s*%(?%s*['\"]") then
    return nil, ""
  end

  if ty == "table_constructor" then
    local n = count_fields(value)
    return "table", n > 0 and (n .. (n == 1 and " field" or " fields")) or "empty"
  end
  if ty == "number" or ty == "string" or ty == "true" or ty == "false" then
    return "constant", condense(text)
  end
  return "binding", condense(text)
end

---Name of the identifier the chunk returns, if it returns a bare one.
---
---This is how `local M = {}` gets filtered out. It is not state a reader
---wants listed — it *is* the module, already represented by the node itself
---and by `node.export` — and it appears in essentially every file: measured
---over lib.nvim it was 188 of 600 symbols, 159 of them literally named `M`.
---Filtering on "empty table" instead would have been wrong in the other
---direction, since `local cache = {}` is real module state that happens to
---start empty.
---@param root TSNode
---@param src string
---@return string?
local function returned_name(root, src)
  for i = root:named_child_count() - 1, 0, -1 do
    local child = root:named_child(i)
    if child:type() == "return_statement" then
      local text = vim.treesitter.get_node_text(child, src)
      -- `return M` and `return setmetatable(M, {...})` are the same statement
      -- about which table is the module; the second form is how this tree
      -- adds a `__call` or a lazy `__index`, and missing it left the export
      -- table listed for exactly those files.
      return text:match("^return%s+([%a_][%w_]*)%s*$")
        or text:match("^return%s+setmetatable%s*%(%s*([%a_][%w_]*)")
    end
  end
  return nil
end

---Extract module-scope symbols from an already-parsed tree.
---@param root TSNode Root of the parsed Lua tree.
---@param src string Source text the tree was parsed from.
---@param doc_above fun(row: integer): string[] Doc-comment block immediately above a 0-based row, as `docmap.functions` collects it.
---@return Lib.Docmap.SymbolInfo[]
function M.extract(root, src, doc_above)
  local id_by_name = {}
  for id, name in ipairs(SYMBOL_QUERY.captures) do
    id_by_name[name] = id
  end

  local out = {}
  local seen = {}
  local exported = returned_name(root, src)

  for _, match in SYMBOL_QUERY:iter_matches(root, src) do
    local name_nodes = match[id_by_name.name]
    local value_nodes = match[id_by_name.value]
    local name_node = name_nodes and name_nodes[1]
    local value_node = value_nodes and value_nodes[1]

    if name_node and value_node then
      local name = vim.treesitter.get_node_text(name_node, src)
      local text = vim.treesitter.get_node_text(value_node, src)
      local kind, detail = classify(value_node, text)
      local srow = name_node:range()

      -- A name assigned twice at module scope (a forward declaration filled
      -- in later) is one symbol, reported at its first appearance.
      if kind and name ~= exported and not seen[name] then
        seen[name] = true
        local block = doc_above and doc_above(srow) or {}
        local prose = {}
        for _, raw in ipairs(block) do
          if not raw:match("^%-%-%-@") then
            prose[#prose + 1] = (raw:gsub("^%-%-%-?%s?", ""))
          end
        end
        local summary = require("lib.nvim.docmap.scan").split_summary(table.concat(prose, "\n"))

        out[#out + 1] = {
          name = name,
          kind = kind,
          detail = detail,
          summary = summary,
          line = srow + 1,
        }
      end
    end
  end

  table.sort(out, function(a, b)
    return a.line < b.line
  end)

  return out
end

return M
