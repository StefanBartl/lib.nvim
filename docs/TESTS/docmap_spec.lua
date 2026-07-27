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

  ok(req_edge, "docmap.deps: a require edge exists between the two modules")
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

  vim.fn.delete(root, "rf")
end
