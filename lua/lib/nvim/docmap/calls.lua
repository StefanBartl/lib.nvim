---@module 'lib.nvim.docmap.calls'
--- Call-graph extraction: which function calls which, across the scanned tree.
--- The Caller/Callee half of the Doxygen-shaped picture, and the only stage
--- here that has to reason about names rather than just read them.
---
--- Two steps, deliberately split:
---
---   extract(root, src, defs)  syntax only — every call site, its raw callee
---                             text, and which top-level function encloses it.
---                             Runs inside `docmap.functions.scan_file`, on the
---                             treesitter tree that was parsed there anyway.
---   build(ir, opts)           resolution — turns that raw text into node ids
---                             and function names, using the require aliases
---                             `docmap.deps` collected.
---
--- The split exists because resolution is not a per-file question. `fs.read()`
--- only means something once you know that this file bound `fs` to
--- `lib.nvim.fs` and that some node in the map declares that module. A scanner
--- that tried to answer it file-by-file would either be wrong or would need
--- the whole IR passed into it, which is what `build` is.
---
--- ## What resolves, and what is thrown away
---
--- Four shapes resolve exactly, because each is a syntactic fact rather than
--- a guess:
---
---   fs.read(x)               `fs` is bound by `local fs = require("…fs")`
---   require("…fs").read(x)   the module path is in the call itself
---   M.helper(x)              `M` is a prefix this file's own functions use
---   helper(x)                a bare name matching a file-local `local function`
---
--- Everything else is dropped: `obj:method()` on an unknown receiver,
--- `vim.fs.dirname()` (outside the tree), `M[name]()` (not a name at all).
--- `opts.calls_heuristic` adds one guessed shape back — an unresolved bare
--- name matching exactly one function anywhere in the tree — and marks those
--- edges `confidence = "heuristic"` so the renderer can draw them as the
--- weaker claim they are. It is off by default, because a call graph that
--- confidently draws a wrong edge is worse than one that draws fewer.
---
--- Genuinely invisible to this: dynamic dispatch. `lib.nvim.require`'s lazy and
--- metatable strategies produce calls that appear nowhere in the source, and
--- callbacks handed to `vim.schedule` or stored in tables are calls whose
--- target is a value, not a name. Doxygen has the same blind spot in C++ for
--- the same reason. This is why no call-derived check is ever `error` severity.

local M = {}

-- `name:` covers identifier, dot_index_expression and method_index_expression
-- in one capture; splitting them into three patterns would only move the
-- discrimination from `resolve_callee` (where it is one string match) into the
-- query (where it is three near-identical clauses).
local CALL_QUERY = vim.treesitter.query.parse("lua", "(function_call name: (_) @callee) @call")

---Extract every call site from an already-parsed tree.
---
---`defs` comes from `docmap.functions`, which found the same file's top-level
---function definitions moments earlier; the row ranges are what attribute a
---call to a caller. A call outside any top-level function (module-level
---initialisation) gets `from_fn = nil` and is dropped by `build` — the
---interesting module-level call is `require`, and `docmap.deps` already
---models that as its own edge kind.
---@param root TSNode Root of the parsed Lua tree.
---@param src string Source text the tree was parsed from.
---@param defs { name: string, srow: integer, erow: integer }[] Top-level function ranges, 0-based rows.
---@return Lib.Docmap.RawCall[]
function M.extract(root, src, defs)
  local out = {}

  for id, node in CALL_QUERY:iter_captures(root, src) do
    if CALL_QUERY.captures[id] == "callee" then
      local srow = node:range()
      local callee = vim.treesitter.get_node_text(node, src)

      -- Multi-line callee expressions would carry a newline into the text and
      -- never match any name pattern; skipping them here keeps `resolve_callee`
      -- free of whitespace handling.
      if not callee:find("\n") then
        local from_fn
        for _, def in ipairs(defs) do
          -- Innermost wins: definitions are scanned top-level only, so ranges
          -- never nest, and the first containing one is the only one.
          if srow >= def.srow and srow <= def.erow then
            from_fn = def.name
            break
          end
        end
        out[#out + 1] = { callee = callee, from_fn = from_fn, line = srow + 1 }
      end
    end
  end

  return out
end

---Last dot-separated segment of a declared function name: `M.scan_full` →
---`scan_full`. What a caller writing `docmap.scan_full(...)` actually names,
---since the callee's own `M` is a file-local convention the call site cannot
---see.
---@param name string
---@return string
local function bare(name)
  return name:match("([%w_]+)$") or name
end

---Build the lookup tables `resolve` needs for one node: its own functions by
---declared and bare name, and the prefixes its functions are declared on
---(`M` in `function M.foo()`), which is how a same-file `M.foo()` call is
---told apart from a call through a require alias that happens to be named M.
---@param node Lib.Docmap.Node
---@return table<string, string> by_name
---@return table<string, boolean> self_prefixes
local function index_functions(node)
  local by_name, prefixes = {}, {}
  for _, fn in ipairs(node.functions) do
    by_name[fn.name] = fn.name
    -- Declared name wins over bare name on collision: `M.read` and a
    -- file-local `read` in the same file are two functions, and the qualified
    -- call site is the unambiguous one.
    if by_name[bare(fn.name)] == nil then
      by_name[bare(fn.name)] = fn.name
    end
    local prefix = fn.name:match("^([%w_]+)%.")
    if prefix then
      prefixes[prefix] = true
    end
  end
  return by_name, prefixes
end

---Resolve every node's `calls_raw` into `kind="call"` edges appended to
---`ir.edges`. Mutates `ir` in place; `deps.build` must have run first, since
---resolution reads the require aliases it collected.
---@param ir Lib.Docmap.IR
---@param opts Lib.Docmap.Opts?
---@return Lib.Docmap.Edge[] added
function M.build(ir, opts)
  opts = opts or {}
  local by_module = require("lib.nvim.docmap.deps").module_index(ir)
  ir.edges = ir.edges or {}

  local index = {} ---@type table<string, { by_name: table<string, string>, prefixes: table<string, boolean> }>
  for _, id in ipairs(ir.order) do
    local by_name, prefixes = index_functions(ir.nodes[id])
    index[id] = { by_name = by_name, prefixes = prefixes }
  end

  -- Only built when the heuristic is on: a bare name is a usable hint exactly
  -- when the whole tree declares it once. Names owned by two modules are
  -- ambiguous, and an ambiguous guess is the failure mode this whole flag is
  -- opt-in to avoid, so a second declaration removes the entry rather than
  -- picking a winner.
  local unique_bare = {}
  if opts.calls_heuristic then
    local count = {}
    for _, id in ipairs(ir.order) do
      for _, fn in ipairs(ir.nodes[id].functions) do
        local b = bare(fn.name)
        count[b] = (count[b] or 0) + 1
        unique_bare[b] = { node = id, fn = fn.name }
      end
    end
    for b, n in pairs(count) do
      if n > 1 then
        unique_bare[b] = nil
      end
    end
  end

  local edges = {}
  local seen = {}

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]

    local aliases = {}
    for _, req in ipairs(node.requires_raw or {}) do
      if req.alias and by_module[req.module] then
        aliases[req.alias] = { node = by_module[req.module], member = req.member }
      end
    end

    for _, call in ipairs(node.calls_raw or {}) do
      if call.from_fn then
        local to_id, to_fn, confidence

        -- `require("mod").fn(...)` — an inline require rather than a binding.
        -- Checked first because the callee text starts with the identifier
        -- `require`, which the alias branch below would otherwise try to look
        -- up as a local name. This shape is everywhere in this tree (it is how
        -- a lazy dependency is called without a top-level binding), and it is
        -- exact: the module path is right there in the source.
        local inline_mod, inline_fn =
          call.callee:match("^require%s*%(?%s*['\"]([%w%._%-]+)['\"]%s*%)?%s*%.([%w_%.]+)$")

        local head, rest = call.callee:match("^([%w_]+)%.([%w_%.]+)$")
        if inline_mod and by_module[inline_mod] then
          local target = by_module[inline_mod]
          to_fn = index[target].by_name[inline_fn] or index[target].by_name[bare(inline_fn)]
          to_id = to_fn and target or nil
          confidence = "exact"
        elseif head and aliases[head] then
          local target = aliases[head].node
          to_fn = index[target].by_name[rest] or index[target].by_name[bare(rest)]
          to_id = to_fn and target or nil
          confidence = "exact"
        elseif head and index[id].prefixes[head] then
          to_fn = index[id].by_name[call.callee] or index[id].by_name[bare(rest)]
          to_id = to_fn and id or nil
          confidence = "exact"
        elseif call.callee:match("^[%w_]+$") then
          -- A bare name is a file-local function first; only if this file
          -- declares no such function does the heuristic get a say.
          to_fn = index[id].by_name[call.callee]
          if to_fn then
            to_id, confidence = id, "exact"
          elseif unique_bare[call.callee] then
            to_id = unique_bare[call.callee].node
            to_fn = unique_bare[call.callee].fn
            confidence = "heuristic"
          end
        end

        -- Direct recursion is real but tells the reader nothing a self-loop
        -- on a diagram would not obscure.
        if to_id and to_fn and not (to_id == id and to_fn == call.from_fn) then
          local key = id .. "|" .. call.from_fn .. "|" .. to_id .. "|" .. to_fn
          if not seen[key] then
            seen[key] = true
            edges[#edges + 1] = {
              kind = "call",
              from = id,
              to = to_id,
              from_fn = call.from_fn,
              to_fn = to_fn,
              line = call.line,
              confidence = confidence,
            }
          end
        end
      end
    end
  end

  -- Same reasoning as `deps.build`: each producer sorts its own block and
  -- appends, so `ir.edges` stays byte-deterministic without one comparator
  -- that has to understand every kind's optional fields.
  table.sort(edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    if a.from_fn ~= b.from_fn then
      return a.from_fn < b.from_fn
    end
    if a.to ~= b.to then
      return a.to < b.to
    end
    return a.to_fn < b.to_fn
  end)

  for _, e in ipairs(edges) do
    ir.edges[#ir.edges + 1] = e
  end

  return edges
end

return M
