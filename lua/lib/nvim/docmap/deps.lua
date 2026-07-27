---@module 'lib.nvim.docmap.deps'
--- Require-graph extraction: turns each file's `require(...)` calls into
--- resolved `kind="require"` edges on the IR, plus the `requires`/`required_by`
--- index every renderer and the orphan check read.
---
--- This data already existed in the tree — `check.lua`'s orphan check collected
--- every `require` string in the repo into one flat set, asked "is this module
--- in it?", and threw the rest away. Nothing could draw a dependency graph from
--- that, because the *source* of each require was discarded. Attributing them
--- per file instead costs nothing extra and makes the Deps view, the cycle
--- check and the layering check all fall out of the same pass.
---
--- Extraction is text, not treesitter, deliberately: a `require` call is a
--- string literal on one line in every case that matters, and the header
--- scanner sets the precedent that a cheap reliable reading beats a general
--- one that costs a Lua front end. The alias form (`local x = require("y")`)
--- is recognized separately because it is the one thing that makes call-graph
--- resolution possible at all — see `calls.lua`.
---
--- Unresolvable requires (`vim.*`, other plugins, anything outside the scanned
--- tree) are dropped rather than invented as foreign nodes: the map's promise
--- is "what is in this tree", and a graph half-filled with boxes that have no
--- documentation behind them is noise, not information.

local M = {}

-- Kept in one place because the two forms below must agree on what a module
-- path may contain; `%-` is in the class for plugin names like `nvim-lspconfig`.
local MODULE_CHARS = "[%w%._%-]+"
local REQUIRE = "require%s*%(?%s*['\"](" .. MODULE_CHARS .. ")['\"]"
local ALIAS = "^%s*local%s+([%w_]+)%s*=%s*" .. REQUIRE .. "%s*%)?(.*)$"

---Reject what is not a module path at all.
---
---A dynamic require — `require("lib.lua." .. key)`, which is how this tree's
---aggregators dispatch — puts a string literal in exactly the place the
---pattern above looks, and yields the dangling prefix `lib.lua.`. That never
---resolved to a node, so it cost nothing while unresolved requires were
---simply discarded; the moment they became visible it would have been four
---confident boxes for modules that do not exist. A real module path has no
---empty segment, which is precisely what a leading, trailing or doubled dot
---means.
---@param path string
---@return boolean
local function is_module_path(path)
  return not (path:match("^%.") or path:match("%.$") or path:find("%.%.", 1, false))
end

---Extract every `require` occurrence from already-read source text.
---
---Called from `docmap.functions.scan_file`, which has the file's contents in
---hand anyway — reading it a second time here would double the scan's I/O for
---a regex that fits in the same loop.
---@param src string Full file contents.
---@return Lib.Docmap.RawRequire[]
function M.extract_source(src)
  local out = {}
  local lnum = 0

  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    lnum = lnum + 1

    -- Comment lines are skipped, and this is not a nicety: usage examples in
    -- module headers (`---   local kit = require("lib.nvim.ui.kit")`) are
    -- everywhere in this tree, and counting them produced four confident
    -- require-cycle findings against modules that require nothing of the sort.
    -- A trailing comment on a real line is unaffected — only a line that
    -- *starts* as a comment is dropped.
    local commented = line:match("^%s*%-%-")

    -- The alias form first: it is a strict subset of the general form, so
    -- matching the general one first would consume it and lose the binding.
    -- Spelled as a statement rather than `not commented and line:match(...)`,
    -- which would collapse the three captures to one.
    local alias, mod, tail
    if not commented then
      alias, mod, tail = line:match(ALIAS)
    end
    if alias and is_module_path(mod) then
      out[#out + 1] = {
        module = mod,
        alias = alias,
        member = tail and tail:match("^%.([%w_]+)") or nil,
        line = lnum,
      }
    elseif not commented then
      for m in line:gmatch(REQUIRE) do
        if is_module_path(m) then
          out[#out + 1] = { module = m, alias = nil, member = nil, line = lnum }
        end
      end
    end
  end

  return out
end

-- Every function-shaped node, not just the top-level declarations
-- `docmap.functions` cares about: a lazy require hides inside an anonymous
-- `__index = function(_, k) return require(...)[k] end` just as often as
-- inside a named one, and treating those as load-time dependencies reported
-- `lib.nvim.usercmd ↔ lib.nvim.usercmd.composer` as a cycle that cannot
-- actually happen.
local FN_BODY_QUERY =
  vim.treesitter.query.parse("lua", "[(function_declaration) (function_definition)] @fn")

---Mark which of `requires` sit inside a function body — deferred loads rather
---than load-time dependencies. Both remain real dependency edges; only the
---cycle check distinguishes them, because only load-time cycles can hand a
---module a half-initialised table.
---@param root TSNode Root of the parsed Lua tree for the same source.
---@param src string
---@param requires Lib.Docmap.RawRequire[] Mutated in place.
function M.mark_deferred(root, src, requires)
  if #requires == 0 then
    return
  end

  local spans = {}
  for id, node in FN_BODY_QUERY:iter_captures(root, src) do
    if FN_BODY_QUERY.captures[id] == "fn" then
      local srow, _, erow = node:range()
      spans[#spans + 1] = { srow = srow, erow = erow }
    end
  end

  for _, req in ipairs(requires) do
    local row = req.line - 1
    for _, span in ipairs(spans) do
      if row >= span.srow and row <= span.erow then
        req.deferred = true
        break
      end
    end
  end
end

---Map every declared `@module` path to the node that declares it.
---
---Shared with `calls.lua`, which needs exactly the same index to turn a
---`require` alias into a node id.
---@param ir Lib.Docmap.IR
---@return table<string, string> module_path -> node id
function M.module_index(ir)
  local by_module = {}
  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    if node.module then
      by_module[node.module] = id
    end
  end
  return by_module
end

---Resolve every node's `requires_raw` into `kind="require"` edges, appended to
---`ir.edges`, and fill the `requires`/`required_by` index on each node.
---
---Mutates `ir` in place and is idempotent per scan: `scan()` calls it once,
---right after the walk, so `check()` and the renderers can both assume the
---index exists rather than each rebuilding it.
---@param ir Lib.Docmap.IR
---@return Lib.Docmap.Edge[] added The require edges appended, for callers that want them separately.
function M.build(ir)
  local by_module = M.module_index(ir)
  ir.edges = ir.edges or {}

  local edges = {}
  local incoming = {} ---@type table<string, table<string, boolean>>

  for _, id in ipairs(ir.order) do
    local node = ir.nodes[id]
    node.requires = {}
    node.required_by = {}
    node.requires_external = {}

    local seen_external = {}
    local seen = {}
    for _, req in ipairs(node.requires_raw or {}) do
      local target = by_module[req.module]

      -- Requires that resolve to nothing in this tree are still facts about
      -- the module: `fidget.progress` is a real dependency, it just is not
      -- one this map can draw a documented box for. Kept as plain module
      -- strings rather than invented nodes — the map's promise is "what is in
      -- this tree", and a node with no source, no summary and no functions
      -- behind it would break that. The Deps view materializes them into
      -- boxes on request; nothing else has to know they exist.
      if not target and req.module ~= node.module and not seen_external[req.module] then
        seen_external[req.module] = true
        node.requires_external[#node.requires_external + 1] = req.module
      end
      -- A file requiring its own module is legal (re-entrant lazy loading)
      -- but is a self-loop no layout draws usefully.
      if target and target ~= id then
        local existing = seen[target]
        if existing then
          -- One module required both lazily and at load time is a load-time
          -- dependency: the strictest occurrence decides, and the earliest
          -- line is the one worth linking to.
          if not req.deferred then
            existing.deferred = nil
            existing.line = math.min(existing.line, req.line)
          end
        else
          local edge = {
            kind = "require",
            from = id,
            to = target,
            to_module = req.module,
            deferred = req.deferred or nil,
            line = req.line,
          }
          seen[target] = edge
          edges[#edges + 1] = edge
          node.requires[#node.requires + 1] = target
          incoming[target] = incoming[target] or {}
          incoming[target][id] = true
        end
      end
    end

    table.sort(node.requires)
    table.sort(node.requires_external)
  end

  for target, sources in pairs(incoming) do
    local list = ir.nodes[target].required_by
    for src in pairs(sources) do
      list[#list + 1] = src
    end
    table.sort(list)
  end

  -- Sorted before appending, not after: `ir.edges` holds several edge kinds
  -- with disjoint optional fields, so one comparator over the merged array
  -- would have to special-case every kind. Each producer sorts its own block
  -- and appends; the result is deterministic without a shared comparator.
  table.sort(edges, function(a, b)
    if a.from ~= b.from then
      return a.from < b.from
    end
    return a.to < b.to
  end)

  for _, e in ipairs(edges) do
    ir.edges[#ir.edges + 1] = e
  end

  return edges
end

return M
