-- docs/TESTS/docmap_spec.lua — lib.nvim.docmap.functions, lib.nvim.docmap.check

return function(H)
  local eq, ok = H.eq, H.ok

  -- --------------------------------------------------------- docmap.functions
  local functions = require("lib.nvim.docmap.functions")

  local fixture = H.tmpfile(".lua")
  local fw = assert(io.open(fixture, "w"), "docmap spec: fixture must be writable")
  fw:write(table.concat({
    "local M = {}",
    "",
    "---Does the old thing.",
    "---@generic T",
    "---@param x string the input",
    "---@param opts table? extra options",
    "---@return boolean ok",
    "---@return string? err",
    "---@deprecated use new_thing instead",
    "---@async",
    "---@nodiscard",
    "---@see M.new_thing",
    "---@see nowhere.at.all",
    "---@since v1.2.0",
    "---@example",
    '--- local ok = M.old_thing("x")',
    "--- assert(ok)",
    "function M.old_thing(x, opts)",
    "  return true",
    "end",
    "",
    "---The replacement.",
    "function M.new_thing()",
    "  local function helper()", -- nested: must NOT be scanned
    "    return 1",
    "  end",
    "  return helper()",
    "end",
    "",
    "local function bare_helper(a, b)", -- top-level local function: must be scanned
    "  return a + b",
    "end",
    "",
    "return M",
  }, "\n"))
  fw:close()

  local fns = functions.scan_file(fixture)
  eq(#fns, 3, "docmap.functions: finds exactly the 3 top-level functions, not the nested one")

  local old_thing, new_thing, bare
  for _, f in ipairs(fns) do
    if f.name == "M.old_thing" then
      old_thing = f
    end
    if f.name == "M.new_thing" then
      new_thing = f
    end
    if f.name == "bare_helper" then
      bare = f
    end
  end

  ok(old_thing, "docmap.functions: M.old_thing found")
  eq(
    old_thing.signature,
    "M.old_thing(x, opts)",
    "docmap.functions: signature is the qualified name plus params"
  )
  eq(#old_thing.params, 2, "docmap.functions: 2 @param entries")
  eq(old_thing.params[1].name, "x", "docmap.functions: first param name")
  eq(old_thing.params[1].type, "string", "docmap.functions: first param type")
  eq(old_thing.params[1].desc, "the input", "docmap.functions: first param desc")
  eq(old_thing.params[2].optional, true, "docmap.functions: 'opts?' marks optional")
  eq(#old_thing.returns, 2, "docmap.functions: 2 @return entries")
  eq(old_thing.returns[1].type, "boolean", "docmap.functions: first return type")
  eq(old_thing.returns[1].name, "ok", "docmap.functions: first return name")
  eq(old_thing.deprecated, "use new_thing instead", "docmap.functions: @deprecated text")
  eq(old_thing.async, true, "docmap.functions: @async flag")
  eq(old_thing.nodiscard, true, "docmap.functions: @nodiscard flag")
  eq(#old_thing.see, 2, "docmap.functions: 2 @see targets")
  eq(old_thing.see[1], "M.new_thing", "docmap.functions: first @see target")
  eq(old_thing.since, "v1.2.0", "docmap.functions: @since text")
  eq(old_thing.generic[1], "T", "docmap.functions: @generic name")
  ok(
    old_thing.example and old_thing.example:match("assert%(ok%)"),
    "docmap.functions: @example block captured across multiple lines"
  )
  eq(old_thing.summary, "Does the old thing.", "docmap.functions: leading prose becomes summary")

  ok(new_thing, "docmap.functions: M.new_thing found")
  eq(#new_thing.params, 0, "docmap.functions: M.new_thing has no params")
  eq(new_thing.deprecated, nil, "docmap.functions: undecorated function has no @deprecated")

  ok(bare, "docmap.functions: top-level 'local function bare_helper' is scanned")
  eq(bare.signature, "bare_helper(a, b)", "docmap.functions: bare local function signature")

  -- Undocumented function (no doc comment at all) still gets a FunctionInfo
  -- with empty fields, not skipped — dead-see-target/undocumented-param need
  -- to see it too.
  local fixture2 = H.tmpfile(".lua")
  local fw2 = assert(io.open(fixture2, "w"))
  fw2:write("local M = {}\nfunction M.raw(a, b)\n  return a\nend\nreturn M\n")
  fw2:close()
  local fns2 = functions.scan_file(fixture2)
  eq(#fns2, 1, "docmap.functions: undocumented function is still scanned")
  eq(#fns2[1].params, 0, "docmap.functions: undocumented function has an empty params list")

  -- ------------------------------------------------------------- docmap.check
  local check = require("lib.nvim.docmap.check")

  local function make_ir(functions_by_node)
    local nodes, order = {}, {}
    for id, fns_ in pairs(functions_by_node) do
      nodes[id] = {
        id = id,
        kind = "module",
        name = id,
        path = id,
        source = id .. "/init.lua",
        module = id:gsub("/", "."),
        summary = "x",
        body = "",
        readme = "x.md",
        types = {},
        export = "table",
        parent = nil,
        depth = 0,
        children = {},
        functions = fns_,
      }
      order[#order + 1] = id
    end
    table.sort(order)
    return {
      meta = {
        title = "t",
        source = "lua",
        types_dir = "@types",
        branch = "main",
        schema = 1,
        counts = { module = #order, namespace = 0, file = 0 },
      },
      root = order[1],
      order = order,
      nodes = nodes,
      edges = {},
    }
  end

  local ir = make_ir({
    ["a"] = {
      {
        name = "M.foo",
        signature = "foo(x, y)",
        summary = "",
        line = 1,
        params = { { name = "x", type = "string", optional = false, desc = "" } },
        returns = {},
        generic = {},
        deprecated = nil,
        async = false,
        nodiscard = false,
        see = { "b.bar", "nowhere.real" },
        overload = {},
        example = nil,
        since = nil,
      },
    },
    ["b"] = {
      {
        name = "M.bar",
        signature = "bar()",
        summary = "",
        line = 1,
        params = {},
        returns = {},
        generic = {},
        deprecated = nil,
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
        example = nil,
        since = nil,
      },
    },
  })

  local opts = { root = "/fake", lua_root = "lua", extra_checks = {} }
  local findings = check.run(ir, opts)

  local has_dead_see, has_undoc_param = false, false
  for _, f in ipairs(findings) do
    if f.check == "dead-see-target" then
      has_dead_see = true
      ok(f.message:match("nowhere%.real"), "docmap.check: dead-see-target names the bad target")
    end
    if f.check == "undocumented-param" then
      has_undoc_param = true
      eq(f.severity, "info", "docmap.check: undocumented-param is info-severity")
    end
  end
  ok(has_dead_see, "docmap.check: dead-see-target fires for an unresolvable @see target")
  ok(
    not (function()
        for _, f in ipairs(findings) do
          if f.check == "dead-see-target" and f.message:match("b%.bar") then
            return true
          end
        end
        return false
      end)(),
    "docmap.check: dead-see-target does NOT fire for 'b.bar', which resolves via module+bare-name"
  )
  ok(
    has_undoc_param,
    "docmap.check: undocumented-param fires when signature has more params than @param lines"
  )

  -- ------------------------------------------------------------- docmap.deps
  local deps = require("lib.nvim.docmap.deps")

  local extracted = deps.extract_source(table.concat({
    'local fs = require("demo.fs")',
    'local read = require("demo.io").read',
    'require("demo.side_effect")',
    '---   local x = require("demo.docs_only")', -- a usage example, not a require
    '-- require("demo.commented_out")',
    "function M.lazy()",
    '  return require("demo.deferred")',
    "end",
  }, "\n"))

  eq(#extracted, 4, "docmap.deps: comment lines are not requires")

  -- A dynamic require puts a string literal exactly where the pattern looks,
  -- and yields a dangling prefix that is not a module path at all.
  local dynamic = deps.extract_source(table.concat({
    'local mod = require("demo.lua." .. key)',
    'return require("demo." .. name)',
    'require("..weird")',
    'local ok = require("demo.real")',
  }, "\n"))
  eq(#dynamic, 1, "docmap.deps: dynamic require concatenations are not module paths")
  eq(dynamic[1].module, "demo.real", "docmap.deps: the one real require on those lines survives")

  eq(extracted[1].alias, "fs", "docmap.deps: local binding is captured as an alias")
  eq(extracted[1].module, "demo.fs", "docmap.deps: alias form resolves the module path")
  eq(extracted[2].member, "read", "docmap.deps: trailing field access is captured")
  eq(extracted[3].alias, nil, "docmap.deps: a bare require has no alias")
  eq(extracted[3].module, "demo.side_effect", "docmap.deps: bare require module path")
  eq(extracted[4].module, "demo.deferred", "docmap.deps: requires inside functions are found")

  local no_comment_modules = true
  for _, req in ipairs(extracted) do
    if req.module:match("docs_only") or req.module:match("commented_out") then
      no_comment_modules = false
    end
  end
  ok(no_comment_modules, "docmap.deps: no require is taken from a comment line")

  -- ----------------------------------------------- deps + calls over a tree
  -- A real scan, not a hand-built IR: resolution is the whole point of these
  -- two stages, and it only exists once a module index and require aliases
  -- are in play. Two modules, one requiring and calling into the other.
  local scan = require("lib.nvim.docmap.scan")
  local root = H.tmpfile("_tree")
  local function write(rel, lines)
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: fixture tree must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  write("lua/demo/util/init.lua", {
    "---@module 'demo.util'",
    "--- Utilities.",
    "local M = {}",
    "---Trim it.",
    "function M.trim(s)",
    "  return s",
    "end",
    "return M",
  })
  write("lua/demo/app/init.lua", {
    "---@module 'demo.app'",
    "--- The app.",
    'local util = require("demo.util")',
    'local outside = require("plenary.async")',
    "local M = {}",
    "---Run it.",
    "function M.run(s)",
    "  return util.trim(helper(s))",
    "end",
    "---Helper.",
    "function helper(s)",
    '  return require("demo.util").trim(s)',
    "end",
    "return M",
  })

  local tree = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })

  local app, util = "lua/demo/app", "lua/demo/util"
  eq(#tree.nodes[app].requires, 1, "docmap.deps: app requires exactly one in-tree module")
  eq(tree.nodes[app].requires[1], util, "docmap.deps: the require resolves to the util node")
  eq(tree.nodes[util].required_by[1], app, "docmap.deps: required_by is the reverse index")

  local req_edge, lazy_edge, call_cross, call_local
  for _, e in ipairs(tree.edges) do
    if e.kind == "require" and e.from == app then
      req_edge = e
    end
    if e.kind == "call" and e.from_fn == "M.run" and e.to == util then
      call_cross = e
    end
    if e.kind == "call" and e.from_fn == "M.run" and e.to_fn == "helper" then
      call_local = e
    end
    if e.kind == "call" and e.from_fn == "helper" then
      lazy_edge = e
    end
  end

  -- Stats aggregate over the subtree, not just the node's own directory.
  local root_stats = tree.nodes[tree.root].stats
  eq(root_stats.modules, 2, "docmap.stats: both modules are counted at the root")
  eq(root_stats.files_lua, 2, "docmap.stats: lua files roll up")
  ok(root_stats.lines > 0, "docmap.stats: lines of Lua are counted")
  eq(
    root_stats.functions,
    tree.nodes[app].stats.functions + tree.nodes[util].stats.functions,
    "docmap.stats: the root's function count is the sum of its children's"
  )
  eq(tree.nodes[util].stats.modules, 1, "docmap.stats: a leaf module counts itself")

  ok(req_edge, "docmap.deps: a require edge exists between the two modules")
  -- Unresolvable requires are kept as plain module strings rather than
  -- dropped or turned into invented nodes, so the Deps view can draw them.
  eq(
    #tree.nodes[app].requires_external,
    1,
    "docmap.deps: a require outside the tree is recorded, not discarded"
  )
  eq(
    tree.nodes[app].requires_external[1],
    "plenary.async",
    "docmap.deps: it is kept as the module path as written"
  )
  eq(
    #tree.nodes[util].requires_external,
    0,
    "docmap.deps: a module with only in-tree requires has none"
  )
  local invented = false
  for _, e in ipairs(tree.edges) do
    if e.kind == "require" and e.to_module == "plenary.async" then
      invented = true
    end
  end
  ok(
    not invented,
    "docmap.deps: an external require produces no edge to a node that does not exist"
  )
  eq(req_edge.deferred, nil, "docmap.deps: a top-level require is not marked deferred")
  ok(call_cross, "docmap.calls: a call through a require alias resolves across modules")
  eq(call_cross.to_fn, "M.trim", "docmap.calls: resolves to the declared name in the target")
  eq(call_cross.confidence, "exact", "docmap.calls: alias-resolved calls are exact")
  ok(call_local, "docmap.calls: a bare call to a same-file function resolves locally")
  ok(lazy_edge, "docmap.calls: calls inside a lazily-requiring function still resolve")

  -- Deduped to one edge per (from, to), and the load-time occurrence wins the
  -- `deferred` flag over the lazy one inside `helper`.
  local req_count = 0
  for _, e in ipairs(tree.edges) do
    if e.kind == "require" and e.from == app and e.to == util then
      req_count = req_count + 1
    end
  end
  eq(req_count, 1, "docmap.deps: repeated requires of one module collapse to a single edge")

  -- A cycle among *deferred* requires must not be reported: that is the
  -- deliberate lazy-load pattern, and reporting it drowns the real ones.
  write("lua/demo/util/init.lua", {
    "---@module 'demo.util'",
    "--- Utilities.",
    "local M = {}",
    "---Trim it.",
    "function M.trim(s)",
    '  return require("demo.app") and s',
    "end",
    "return M",
  })
  local cyc = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  local cyc_findings = check.run(cyc, { root = root, source = "lua/demo", lua_root = "lua" })
  local reported_cycle = false
  for _, f in ipairs(cyc_findings) do
    if f.check == "require-cycle" then
      reported_cycle = true
    end
  end
  ok(not reported_cycle, "docmap.check: a cycle closed by a deferred require is not reported")

  -- ---------------------------------------------------- command.find_node
  -- `:LibMap graph <name>` has to resolve the names people actually type.
  -- A namespace declares no @module at all, so matching on that alone missed
  -- exactly the directories a dependency graph is most interesting at.
  local command = require("lib.nvim.docmap.command")

  eq(
    command.find_node(cyc, "demo.app", "lua"),
    "lua/demo/app",
    "docmap.command: resolves a declared @module path"
  )
  eq(
    command.find_node(cyc, "lua/demo/util", "lua"),
    "lua/demo/util",
    "docmap.command: resolves a raw node id"
  )
  eq(
    command.find_node(cyc, "demo", "lua"),
    "lua/demo",
    "docmap.command: resolves a namespace by its path-implied module name"
  )
  eq(
    command.find_node(cyc, "nope.nope", "lua"),
    nil,
    "docmap.command: an unknown name resolves to nil rather than a wrong node"
  )

  -- ---------------------------------------------- symbols and subtree stats
  local sym_fixture = H.tmpfile(".lua")
  local sfw = assert(io.open(sym_fixture, "w"), "docmap spec: symbol fixture must be writable")
  sfw:write(table.concat({
    "local M = {}",
    "---Cache of resolved roots.",
    "local CACHE = { a = 1, b = 2, c = 3 }",
    "local MAX = 42",
    'local fs = require("demo.fs")', -- a dependency, not a symbol
    "local uv = vim.uv or vim.loop",
    "M.defaults = { x = 1 }",
    "M.handler = function() return 1 end", -- a function, not a symbol
    "function M.go()",
    "  local inner = {}", -- nested: not module scope
    "  return inner",
    "end",
    "return M",
  }, "\n"))
  sfw:close()

  local _, _, _, syms, loc = functions.scan_file(sym_fixture)
  local by_sym = {}
  for _, s in ipairs(syms) do
    by_sym[s.name] = s
  end

  eq(loc, 13, "docmap.functions: reports the file's line count")
  ok(by_sym.CACHE, "docmap.symbols: a module-scope table is reported")
  eq(by_sym.CACHE.kind, "table", "docmap.symbols: a table constructor is a table")
  eq(by_sym.CACHE.detail, "3 fields", "docmap.symbols: a table's detail is its field count")
  eq(
    by_sym.CACHE.summary,
    "Cache of resolved roots.",
    "docmap.symbols: the doc comment above it becomes the summary"
  )
  eq(by_sym.MAX.kind, "constant", "docmap.symbols: a literal is a constant")
  eq(by_sym.MAX.detail, "42", "docmap.symbols: a constant's detail is the literal")
  eq(by_sym.uv.kind, "binding", "docmap.symbols: anything else is a binding")
  eq(by_sym["M.defaults"].kind, "table", "docmap.symbols: M.x = {} is reported too")

  -- The two exclusions are the point: another stage owns each of them, and
  -- reporting them twice would be two places to keep in sync.
  eq(by_sym.fs, nil, "docmap.symbols: a require binding is left to docmap.deps")
  eq(by_sym["M.handler"], nil, "docmap.symbols: a function value is left to docmap.functions")
  eq(by_sym.inner, nil, "docmap.symbols: a local inside a function body is not module scope")

  -- The export table is the module, not state it holds. Filtering it matters
  -- at scale: over lib.nvim it was 188 of 600 entries before this.
  eq(by_sym.M, nil, "docmap.symbols: the returned export table is not listed as a symbol")

  local meta_fixture = H.tmpfile(".lua")
  local mfw = assert(io.open(meta_fixture, "w"))
  mfw:write(table.concat({
    "local M = {}",
    "local state = {}",
    "return setmetatable(M, { __call = function() return 1 end })",
  }, "\n"))
  mfw:close()
  local _, _, _, meta_syms = functions.scan_file(meta_fixture)
  local meta_names = {}
  for _, s in ipairs(meta_syms) do
    meta_names[s.name] = true
  end
  eq(
    meta_names.M,
    nil,
    "docmap.symbols: `return setmetatable(M, …)` also identifies the export table"
  )
  ok(meta_names.state, "docmap.symbols: other module-scope tables survive that filter")

  -- ------------------------------------------------ deps.path / deps.impact
  -- A four-module chain plus a shortcut, so "shortest" is a real claim:
  --   one -> two -> three -> four,  and  one -> four directly (lazy)
  local gr = H.tmpfile("_graph")
  local function gwrite(rel, lines)
    local abs = gr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: graph fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end
  local function mod(name, requires, lazy)
    local lines = { ("---@module 'g.%s'"):format(name), "--- M.", "local M = {}" }
    for _, r in ipairs(requires) do
      if lazy then
        lines[#lines + 1] = "---Lazy."
        lines[#lines + 1] = ("function M.get_%s()"):format(r)
        lines[#lines + 1] = ('  return require("g.%s")'):format(r)
        lines[#lines + 1] = "end"
      else
        table.insert(lines, 3, ('local _%s = require("g.%s")'):format(r, r))
      end
    end
    lines[#lines + 1] = "return M"
    gwrite(("lua/g/%s/init.lua"):format(name), lines)
  end
  mod("two", { "three" })
  mod("three", { "four" })
  mod("four", {})
  -- `one` reaches `four` in three load-time hops or one lazy hop.
  gwrite("lua/g/one/init.lua", {
    "---@module 'g.one'",
    "--- One.",
    'local _two = require("g.two")',
    "local M = {}",
    "---Lazy.",
    "function M.late()",
    '  return require("g.four")',
    "end",
    "return M",
  })

  local gir = scan.scan({ root = gr, source = "lua/g", lua_root = "lua" })
  local chain = deps.path(gir, "lua/g/one", "lua/g/four")
  ok(chain, "deps.path: finds a path")
  eq(#chain, 1, "deps.path: takes the one-hop lazy shortcut over the three-hop chain")
  eq(chain[1].deferred, true, "deps.path: and reports that the hop is lazy")

  -- Without the shortcut the long way is the answer, and the chain must be
  -- contiguous — a reconstruction bug shows up here and nowhere else.
  local long = deps.path(gir, "lua/g/two", "lua/g/four")
  eq(#long, 2, "deps.path: the multi-hop route when there is no shortcut")
  eq(long[1].from, "lua/g/two", "deps.path: the chain starts at the source")
  eq(long[1].to, long[2].from, "deps.path: and is contiguous")
  eq(long[2].to, "lua/g/four", "deps.path: and ends at the target")

  eq(#deps.path(gir, "lua/g/one", "lua/g/one"), 0, "deps.path: a node reaches itself in zero hops")
  eq(deps.path(gir, "lua/g/four", "lua/g/one"), nil, "deps.path: nil when unreachable")
  eq(deps.path(gir, "lua/g/one", "nope"), nil, "deps.path: nil for an unknown node")

  local hull, direct = deps.impact(gir, "lua/g/four")
  eq(#hull, 3, "deps.impact: the transitive closure of required_by")
  eq(direct, 2, "deps.impact: and the direct count alongside it")
  eq(hull[1] < hull[2], true, "deps.impact: sorted")
  eq(#(deps.impact(gir, "lua/g/one")), 0, "deps.impact: nothing depends on the top of the chain")
  eq(#(deps.impact(gir, "nope")), 0, "deps.impact: an unknown node has no dependents")

  -- ---------------------------------------------------------- render.dot
  local dot = require("lib.nvim.docmap.render.dot")
  local whole = dot.render(gir, { kind = "require" })
  ok(whole:match("^// require graph"), "render.dot: leads with a comment naming the graph")
  ok(whole:find("digraph docmap {", 1, true), "render.dot: emits a digraph")
  ok(whole:find('"lua/g/one" -> "lua/g/two"', 1, true), "render.dot: quotes node ids and edges")
  ok(whole:find('label="lazy"', 1, true), "render.dot: marks deferred requires")
  eq(whole, dot.render(gir, { kind = "require" }), "render.dot: byte-stable for the same IR")

  -- Scope is bounded. Unbounded reachability sounds right and is not: in a
  -- connected dependency graph almost everything reaches almost everything,
  -- and a scope that excludes nothing is not a scope.
  local near = dot.render(gir, { kind = "require", scope = "lua/g/four", hops = 1 })
  local far = dot.render(gir, { kind = "require", scope = "lua/g/four", hops = 3 })
  local function node_count(s)
    return select(2, s:gsub("%[label=", ""))
  end
  ok(node_count(near) < node_count(far), "render.dot: a smaller hop budget yields a smaller graph")
  ok(node_count(near) > 0, "render.dot: and still contains the neighbourhood")

  local calls_dot = dot.render(gir, { kind = "call" })
  ok(
    calls_dot:match("^// call graph"),
    "render.dot: the call graph is a different graph, not a relabelled one"
  )

  vim.fn.delete(gr, "rf")

  -- --------------------------------------- layers, heuristic, handle queries
  -- Three features that shipped with no coverage at all. The heuristic one in
  -- particular is only worth having if it stays *silent* on an ambiguous name,
  -- which is precisely the case a happy-path test would miss.
  local heur_root = H.tmpfile("_heur")
  local function hwrite(rel, lines)
    local abs = heur_root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: heuristic fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  -- `only_here` is declared once in the tree; `ambiguous` is declared twice.
  hwrite("lua/demo/a/init.lua", {
    "---@module 'demo.a'",
    "--- A.",
    "local M = {}",
    "---U.",
    "function M.only_here()",
    "  return 1",
    "end",
    "---S.",
    "function M.ambiguous()",
    "  return 1",
    "end",
    "return M",
  })
  hwrite("lua/demo/b/init.lua", {
    "---@module 'demo.b'",
    "--- B.",
    "local M = {}",
    "---S.",
    "function M.ambiguous()",
    "  return 2",
    "end",
    "return M",
  })
  -- Calls both by bare name, with no require anywhere to resolve them.
  hwrite("lua/demo/c/init.lua", {
    "---@module 'demo.c'",
    "--- C.",
    "local M = {}",
    "---Go.",
    "function M.go()",
    "  return only_here() + ambiguous()",
    "end",
    "return M",
  })

  local base = { root = heur_root, source = "lua/demo", lua_root = "lua" }
  local function guessed_edges(o)
    local out = {}
    for _, e in ipairs(scan.scan(o).edges) do
      if e.kind == "call" and e.from == "lua/demo/c" then
        out[#out + 1] = e
      end
    end
    return out
  end

  eq(#guessed_edges(base), 0, "docmap.calls: unresolvable bare calls are dropped by default")

  local guessed = guessed_edges(vim.tbl_extend("force", base, { calls_heuristic = true }))
  eq(#guessed, 1, "docmap.calls: the heuristic guesses only the tree-unique name")
  eq(guessed[1].to_fn, "M.only_here", "docmap.calls: it guesses the right one")
  eq(guessed[1].confidence, "heuristic", "docmap.calls: guessed edges are marked as such")

  -- The important half: a name owned by two modules must produce no edge at
  -- all rather than an arbitrary winner.
  local guessed_ambiguous = false
  for _, e in ipairs(guessed) do
    if e.to_fn == "M.ambiguous" then
      guessed_ambiguous = true
    end
  end
  ok(not guessed_ambiguous, "docmap.calls: an ambiguous name is left unresolved, not picked")

  -- layer-violation: the rule direction has to matter, and the prefix has to
  -- respect module-path segments rather than being a raw string prefix.
  local layered = vim.tbl_extend("force", base, {
    layers = { { from = "demo.a", to = "demo.b" } },
  })
  local function layer_hits(o)
    local n = 0
    for _, f in ipairs(check.run(scan.scan(o), o)) do
      if f.check == "layer-violation" then
        n = n + 1
      end
    end
    return n
  end
  eq(layer_hits(layered), 0, "docmap.check: layer-violation is silent when no edge breaks the rule")

  hwrite("lua/demo/a/init.lua", {
    "---@module 'demo.a'",
    "--- A.",
    'local b = require("demo.b")',
    "local M = {}",
    "---U.",
    "function M.only_here()",
    "  return b",
    "end",
    "return M",
  })
  eq(layer_hits(layered), 1, "docmap.check: layer-violation fires on a rule-breaking require")
  eq(
    layer_hits(vim.tbl_extend("force", base, { layers = { { from = "demo.b", to = "demo.a" } } })),
    0,
    "docmap.check: the rule is directional — the reverse does not fire"
  )
  eq(
    layer_hits(vim.tbl_extend("force", base, { layers = { { from = "demo.", to = "demo.b" } } })),
    0,
    "docmap.check: prefixes match whole path segments, so 'demo.' matches nothing"
  )

  -- Handle graph queries, against a live install().
  local handle = require("lib.nvim.docmap").install(base)
  eq(#handle.requires("lua/demo/a"), 1, "docmap.handle: requires() returns the outgoing edge")
  eq(#handle.required_by("lua/demo/b"), 1, "docmap.handle: required_by() is the reverse")
  eq(
    #handle.callers("lua/demo/a#M.only_here"),
    0,
    "docmap.handle: callers() of an uncalled function is empty, not nil"
  )
  -- `ensure_watch` upgrades an installed handle in place. The case it exists
  -- for: `command.setup()` installs with the plain config, which sets no
  -- `watch`, so a `:LibMap` earlier in the session left a non-watching handle
  -- that `:LibBrowse live` then reused — a "live" view that never re-scanned.
  -- Upgrading rather than re-installing is what keeps the subscribers, since
  -- `install()` treats a collision as replace and drops them.
  local registry = require("lib.nvim.docmap.registry")
  -- The group name is keyed on the *normalized* root, the same way the
  -- registry keys its entries — a raw tempname carries backslashes on Windows.
  local watch_group = "LibDocmapWatch:"
    .. require("lib.nvim.docmap.browse.source").norm_root(heur_root)
  local function watching()
    local got, aus = pcall(vim.api.nvim_get_autocmds, { group = watch_group })
    return got and #aus > 0
  end

  local notified = 0
  handle.on_change(function()
    notified = notified + 1
  end)

  eq(watching(), false, "docmap.registry: install() without watch does not watch")
  eq(registry.ensure_watch(heur_root), true, "docmap.registry: ensure_watch upgrades it")
  eq(watching(), true, "docmap.registry: the watch is live afterwards")
  handle.rescan()
  ok(notified > 0, "docmap.registry: the on_change subscriber survives the upgrade")
  eq(registry.ensure_watch(heur_root), true, "docmap.registry: ensure_watch is idempotent")
  eq(
    registry.ensure_watch(heur_root .. "/nowhere"),
    false,
    "docmap.registry: ensure_watch on an uninstalled root is a no-op, not an error"
  )

  handle.uninstall()
  eq(watching(), false, "docmap.registry: uninstall tears the watch down again")

  -- --------------------------------------------------- the watch, end to end
  -- Assumed untestable headlessly at first, which was wrong: `vim.wait` pumps
  -- the event loop, so a real `:write` reaches BufWritePost and the debounced
  -- rescan completes inside the test.
  local live_root = H.tmpfile("_live")
  local function lwrite(rel, lines)
    local abs = live_root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: live fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
    return abs
  end

  local watched_file = lwrite("lua/demo/a/init.lua", {
    "---@module 'demo.a'",
    "--- A.",
    "local M = {}",
    "---One.",
    "function M.one()",
    "  return 1",
    "end",
    "return M",
  })
  -- Deliberately outside `source`: writing here must not trigger anything.
  local outsider = lwrite("notes/scratch.lua", { "-- not part of the scanned tree" })

  local live = require("lib.nvim.docmap").install({
    root = live_root,
    source = "lua/demo",
    lua_root = "lua",
    watch = true,
    watch_ms = 40,
  })
  local rescans = 0
  live.on_change(function()
    rescans = rescans + 1
  end)

  eq(#live.ir().nodes["lua/demo/a"].functions, 1, "docmap.watch: one function before the edit")

  vim.cmd.edit(vim.fn.fnameescape(watched_file))
  vim.api.nvim_buf_set_lines(0, 7, 7, false, {
    "---Two.",
    "function M.two()",
    "  return 2",
    "end",
  })
  vim.cmd("silent write")
  local settled = vim.wait(5000, function()
    return rescans > 0
  end, 25)

  ok(settled, "docmap.watch: writing a file under source triggers a rescan")
  eq(
    #live.ir().nodes["lua/demo/a"].functions,
    2,
    "docmap.watch: and the handle's IR reflects the edit afterwards"
  )

  -- The scope check is the fragile half: an autocmd *glob* over the source
  -- directory silently never fires on Windows, because Vim matches the raw
  -- OS-native buffer path against a forward-slash pattern. This asserts the
  -- other direction — that the explicit subpath check does not over-match.
  local before_outside = rescans
  vim.cmd.edit(vim.fn.fnameescape(outsider))
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "-- touched" })
  vim.cmd("silent write")
  vim.wait(300, function()
    return false
  end, 25)
  eq(rescans, before_outside, "docmap.watch: a write outside source does not rescan")

  live.uninstall()
  vim.cmd("silent! %bwipeout!")
  vim.fn.delete(live_root, "rf")

  vim.fn.delete(heur_root, "rf")
  vim.fn.delete(root, "rf")
end
