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
  eq(old_thing.internal, false, "docmap.functions: @internal defaults to false")

  -- `@internal` marks implementation rather than published surface. It is
  -- what lets every "is this used" question stop guessing from the shape of
  -- a name.
  local fixture3 = H.tmpfile(".lua")
  local fw3 = assert(io.open(fixture3, "w"))
  fw3:write(table.concat({
    "local M = {}",
    "---Plumbing.",
    "---@internal",
    "---@param a string",
    "function M.plumbing(a, b)",
    "  return a, b",
    "end",
    "return M",
  }, "\n"))
  fw3:close()
  local fns3 = functions.scan_file(fixture3)
  eq(fns3[1].internal, true, "docmap.functions: @internal is parsed")

  -- `@todo`/`@bug`/`@test` feed the Notes tab's aggregate lists (Doxygen's
  -- Todo/Bug/Test lists). Arrays rather than single strings on purpose: one
  -- list entry per occurrence, so a function with two open todos keeps both.
  -- lua-language-server ignores these tags rather than diagnosing them as
  -- unknown, which is what makes them safe to introduce (checked against
  -- 3.18.2 with --check before they were added).
  local fixture4 = H.tmpfile(".lua")
  local fw4 = assert(io.open(fixture4, "w"))
  fw4:write(table.concat({
    "local M = {}",
    "---Needs work.",
    "---@todo make this async",
    "---@todo and handle cancellation",
    "---@bug leaks a handle on error",
    "---@test covered by t_spec.lua",
    "function M.rough() end",
    "---Nothing flagged.",
    "function M.clean() end",
    "return M",
  }, "\n"))
  fw4:close()
  local fns4 = functions.scan_file(fixture4)
  local rough, clean
  for _, f in ipairs(fns4) do
    if f.name == "M.rough" then
      rough = f
    end
    if f.name == "M.clean" then
      clean = f
    end
  end
  eq(#rough.todo, 2, "docmap.functions: a repeated @todo keeps every occurrence")
  eq(rough.todo[1], "make this async", "docmap.functions: @todo text, first occurrence")
  eq(rough.todo[2], "and handle cancellation", "docmap.functions: @todo entries stay in order")
  eq(rough.bug[1], "leaks a handle on error", "docmap.functions: @bug is parsed")
  eq(rough.test[1], "covered by t_spec.lua", "docmap.functions: @test is parsed")
  eq(#clean.todo, 0, "docmap.functions: an untagged function gets empty todo/bug/test arrays")
  eq(#clean.bug, 0, "docmap.functions: @bug defaults to an empty array, never nil")
  eq(#clean.test, 0, "docmap.functions: @test defaults to an empty array, never nil")

  -- cyclomatic_complexity: one decision point each for if/elseif/while/for/
  -- repeat, plus one per and/or — verified against the exact shape used to
  -- design the treesitter query in the first place (real inspection of a
  -- parsed tree, not a guess at node types).
  eq(old_thing.complexity, 1, "docmap.functions: a straight-line function has complexity 1")
  eq(
    new_thing.complexity,
    1,
    "docmap.functions: a nested closure with no branches of its own adds nothing"
  )

  local fixture5 = H.tmpfile(".lua")
  local fw5 = assert(io.open(fixture5, "w"))
  fw5:write(table.concat({
    "local M = {}",
    "function M.branchy(x)",
    "  if x == 1 then",
    "    return 1",
    "  elseif x == 2 then",
    "    return 2",
    "  end",
    "  while x > 0 do",
    "    x = x - 1",
    "  end",
    "  for i = 1, 10 do",
    "    print(i)",
    "  end",
    "  repeat",
    "    x = x + 1",
    "  until x > 5",
    "  local y = x and 1 or 2",
    "  return y",
    "end",
    "return M",
  }, "\n"))
  fw5:close()
  local branchy = functions.scan_file(fixture5)[1]
  -- 1 (base) + if + elseif + while + for + repeat + and + or = 8
  eq(
    branchy.complexity,
    8,
    "docmap.functions: complexity counts if/elseif/while/for/repeat/and/or, one each"
  )

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

  local function make_ir(functions_by_node, edges)
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
      edges = edges or {},
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

  -- The same function marked `@internal` must not be nagged about: its
  -- documentation bar is the author's own, and nagging is how a heuristic
  -- check earns a place on someone's ignore list.
  local internal_ir = make_ir({ ["a"] = fns3 })
  local internal_nagged = false
  for _, f in ipairs(check.run(internal_ir, opts)) do
    if f.check == "undocumented-param" then
      internal_nagged = true
    end
  end
  eq(internal_nagged, false, "docmap.check: undocumented-param skips an @internal function")

  -- ------------------------------------------------- param-name-mismatch (R5)
  -- undocumented-param only ever compares counts, so a renamed parameter
  -- whose @param line was never updated passes silently as long as both
  -- lists are the same length. This is the case it cannot see.
  local function param(name)
    return { name = name, type = "any", optional = false, desc = "" }
  end

  local mismatch_ir = make_ir({
    ["a"] = {
      {
        name = "M.resize",
        signature = "resize(width, height)",
        summary = "",
        line = 1,
        params = { param("w"), param("height") }, -- renamed width -> w in code, doc not updated
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
      },
      -- A colon-declared method whose own `self` is documented explicitly —
      -- real, legitimate LuaCATS style (verified against this repo's own
      -- Lru:get/Lru:put) that the implicit-self exclusion must not flag.
      {
        name = "M:put",
        signature = "put(key, value)",
        summary = "",
        line = 5,
        params = { param("self"), param("key"), param("value") },
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
      },
    },
  })
  local mismatch_findings = check.run(mismatch_ir, opts)

  local resize_mismatch, put_mismatch = {}, {}
  for _, f in ipairs(mismatch_findings) do
    if f.check == "param-name-mismatch" then
      if f.message:match("^M%.resize") then
        resize_mismatch[#resize_mismatch + 1] = f
      elseif f.message:match("^M:put") then
        put_mismatch[#put_mismatch + 1] = f
      end
    end
  end
  eq(
    #resize_mismatch,
    1,
    "docmap.check: param-name-mismatch fires once for the one renamed parameter"
  )
  ok(
    resize_mismatch[1]
      and resize_mismatch[1].message:match("'w'")
      and resize_mismatch[1].message:match("'width'"),
    "docmap.check: param-name-mismatch names both the doc's name and the signature's"
  )
  eq(
    resize_mismatch[1] and resize_mismatch[1].severity,
    "info",
    "docmap.check: param-name-mismatch is info-severity, same as undocumented-param"
  )
  eq(
    #put_mismatch,
    0,
    "docmap.check: an explicitly-documented 'self' on a colon method is not a mismatch"
  )

  -- dead-function: local functions and @internal ones are checked
  -- unconditionally; an ordinary exported function only under opts.dead_code.
  local function fn_info(name, over)
    over = over or {}
    return vim.tbl_extend("force", {
      name = name,
      signature = name .. "()",
      summary = "",
      line = 1,
      params = {},
      returns = {},
      generic = {},
      deprecated = nil,
      async = false,
      nodiscard = false,
      internal = false,
      see = {},
      overload = {},
      example = nil,
      since = nil,
    }, over)
  end

  local function has_dead_function(list, name)
    for _, f in ipairs(list) do
      if f.check == "dead-function" and f.message:match("^" .. name:gsub("%.", "%%.")) then
        return true
      end
    end
    return false
  end

  local dead_ir = make_ir({
    ["a"] = {
      fn_info("bare_dead"), -- local function, no caller -> dead
      fn_info("bare_called"), -- local function, has a caller -> not dead
      fn_info("M.internal_dead", { internal = true }), -- @internal, no caller -> dead
      fn_info("M.internal_called", { internal = true }), -- @internal, has a caller -> not dead
      fn_info("M.public_uncalled"), -- ordinary export, no caller -> only under dead_code
      fn_info("M.public_called"), -- ordinary export, has a caller -> never dead
    },
  }, {
    { kind = "call", from = "a", to = "a", from_fn = "M.public_called", to_fn = "bare_called" },
    {
      kind = "call",
      from = "a",
      to = "a",
      from_fn = "M.public_called",
      to_fn = "M.internal_called",
    },
    { kind = "call", from = "a", to = "a", from_fn = "bare_called", to_fn = "M.public_called" },
  })

  local default_findings = check.run(dead_ir, opts)
  ok(
    has_dead_function(default_findings, "bare_dead"),
    "docmap.check: dead-function fires for an uncalled local function"
  )
  ok(
    not has_dead_function(default_findings, "bare_called"),
    "docmap.check: dead-function does not fire for a called local function"
  )
  ok(
    has_dead_function(default_findings, "M.internal_dead"),
    "docmap.check: dead-function fires for an uncalled @internal function"
  )
  ok(
    not has_dead_function(default_findings, "M.internal_called"),
    "docmap.check: dead-function does not fire for a called @internal function"
  )
  ok(
    not has_dead_function(default_findings, "M.public_uncalled"),
    "docmap.check: dead-function does NOT fire for an uncalled exported function by default"
  )
  ok(
    not has_dead_function(default_findings, "M.public_called"),
    "docmap.check: dead-function never fires for a called exported function"
  )
  for _, f in ipairs(default_findings) do
    if f.check == "dead-function" then
      eq(f.severity, "info", "docmap.check: dead-function is always info-severity")
    end
  end

  local dead_code_findings = check.run(dead_ir, vim.tbl_extend("force", opts, { dead_code = true }))
  ok(
    has_dead_function(dead_code_findings, "M.public_uncalled"),
    "docmap.check: opts.dead_code = true also fires for an uncalled exported function"
  )
  ok(
    not has_dead_function(dead_code_findings, "M.public_called"),
    "docmap.check: opts.dead_code = true still skips a called exported function"
  )

  -- ------------------------------------------------------------ docmap.luals
  -- `merge` is the half of luals.lua that needs no lua-language-server: IR +
  -- parsed doc.json in, mutated IR out. The fixture below reproduces the real
  -- --doc shapes exactly as verified against lua-language-server 3.18.2 —
  -- notably that a class's parents live on `defines[1].extends` (an array,
  -- one element per parent) and NOT on the entry, and that each element is
  -- `{ type = "doc.extends.name", view = "<ParentName>" }`. An alias never
  -- carries `extends`, even when it aliases a class; that was checked too,
  -- because the opposite would manufacture inheritance that does not exist.
  local luals = require("lib.nvim.docmap.luals")

  local function ext(view)
    return { type = "doc.extends.name", view = view }
  end
  local function class_entry(name, extends_list)
    return {
      name = name,
      desc = "",
      fields = {},
      defines = { { type = "doc.class", file = "@types/init.lua", extends = extends_list } },
    }
  end

  local luals_ir = {
    order = { "n" },
    nodes = {
      n = {
        id = "n",
        parent = nil,
        types = { "lua/@types/init.lua" },
        stats = { types = 0 },
      },
    },
    edges = {},
  }

  luals.merge(luals_ir, {
    class_entry("D.Root", nil), -- no parent: no `extends` key at all
    class_entry("D.Child", { ext("D.Root") }),
    class_entry("D.Multi", { ext("D.Root"), ext("D.Other") }),
    class_entry("D.Other", nil),
    class_entry("D.Orphan", { ext("D.Missing") }), -- parent not declared anywhere
    class_entry("D.Self", { ext("D.Self") }), -- degenerate, must not self-loop
    {
      name = "D.Alias",
      desc = "",
      fields = {},
      defines = { { type = "doc.alias", file = "@types/init.lua" } },
    },
  }, "lua")

  local by_class = {}
  for _, t in ipairs(luals_ir.nodes.n.types_detail or {}) do
    by_class[t.name] = t
  end

  eq(
    #(by_class["D.Root"].extends or {}),
    0,
    "docmap.luals: a class with no parent gets an empty extends"
  )
  eq(
    by_class["D.Child"].extends[1],
    "D.Root",
    "docmap.luals: single parent parsed from defines[1].extends"
  )
  eq(#by_class["D.Multi"].extends, 2, "docmap.luals: multiple inheritance keeps both parents")
  eq(by_class["D.Multi"].extends[2], "D.Other", "docmap.luals: parents stay in source order")
  eq(#(by_class["D.Alias"].extends or {}), 0, "docmap.luals: an alias never carries extends")
  eq(
    by_class["D.Orphan"].extends[1],
    "D.Missing",
    "docmap.luals: an unresolvable parent is still recorded on the class"
  )

  local ext_pairs = {}
  for _, e in ipairs(luals_ir.edges) do
    if e.kind == "extends" then
      ext_pairs[e.from_class .. " -> " .. e.to_class] = true
      eq(e.from, "n", "docmap.luals: extends edge carries the owning node id")
      eq(e.via, nil, "docmap.luals: extends edges have no `via` — nothing mediates inheritance")
    end
  end
  ok(ext_pairs["D.Child -> D.Root"], "docmap.luals: a resolvable parent produces an extends edge")
  ok(
    ext_pairs["D.Multi -> D.Root"],
    "docmap.luals: multiple inheritance emits an edge per parent (1/2)"
  )
  ok(
    ext_pairs["D.Multi -> D.Other"],
    "docmap.luals: multiple inheritance emits an edge per parent (2/2)"
  )
  ok(
    not ext_pairs["D.Orphan -> D.Missing"],
    "docmap.luals: a parent outside the map produces no edge (kept readable on the class instead)"
  )
  ok(
    not ext_pairs["D.Self -> D.Self"],
    "docmap.luals: a class listing itself never becomes a self-loop"
  )

  -- Deterministic order: --check compares the artifact byte for byte, so two
  -- runs over unchanged input must emit these in the same sequence.
  local ext_seq = {}
  for _, e in ipairs(luals_ir.edges) do
    if e.kind == "extends" then
      ext_seq[#ext_seq + 1] = e.from_class .. ">" .. e.to_class
    end
  end
  eq(
    table.concat(ext_seq, ","),
    "D.Child>D.Root,D.Multi>D.Other,D.Multi>D.Root",
    "docmap.luals: extends edges are emitted sorted by class name pair"
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

  -- ------------------------------------------------------ tagfiles.resolve
  -- `demo.app` (built above) requires `plenary.async`, which resolves to
  -- nothing *in this tree* — exactly the requires_external case tag_files
  -- exists to resolve against another project's own committed artifact,
  -- instead of leaving the Deps view an inert dead end.
  local tagfiles = require("lib.nvim.docmap.tagfiles")
  local docmap = require("lib.nvim.docmap")

  local ext_root = H.tmpfile("_plenary")
  local function ext_write(rel, lines)
    local abs = ext_root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: tag-file fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end
  ext_write("lua/plenary/async/init.lua", {
    "---@module 'plenary.async'",
    "--- Fixture standing in for a real external project.",
    "local M = {}",
    "return M",
  })
  local ext_ir = scan.scan({ root = ext_root, source = "lua/plenary", lua_root = "lua" })
  vim.fn.mkdir(ext_root .. "/docs/map", "p")
  local ext_fd =
    assert(io.open(ext_root .. "/docs/map/module_map.json", "w"), "docmap spec: writable")
  ext_fd:write(docmap.to_json(ext_ir))
  ext_fd:close()

  tagfiles.resolve(tree, {
    root = root,
    lua_root = "lua",
    tag_files = { plenary = ext_root .. "/docs/map" },
  })
  ok(tree.tag_links["plenary.async"], "docmap.tagfiles: resolves against the external artifact")
  eq(
    tree.tag_links["plenary.async"].title,
    "plenary.async",
    "docmap.tagfiles: title is the external node's declared @module"
  )
  eq(
    tree.tag_links["plenary.async"].html,
    (ext_root:gsub("\\", "/")) .. "/docs/map/index.html#lua/plenary/async",
    "docmap.tagfiles: html is that project's own page, fragment = its node id"
  )

  local tree_none = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  tagfiles.resolve(tree_none, { root = root, lua_root = "lua" })
  eq(
    next(tree_none.tag_links),
    nil,
    "docmap.tagfiles: an empty table, not nil, when opts.tag_files is unset"
  )

  local tree_miss = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  tagfiles.resolve(tree_miss, {
    root = root,
    lua_root = "lua",
    tag_files = { ["some.other.project"] = ext_root .. "/docs/map" },
  })
  eq(
    next(tree_miss.tag_links),
    nil,
    "docmap.tagfiles: a prefix that matches nothing resolves nothing, not an error"
  )

  -- ------------------------------------------------------ coverage.resolve
  -- Real spec-file text, not a hand-built name list: the whole point is
  -- that a bare name mentioned in a test file — the way a spec actually
  -- calls a function — is what lights `tested` up.
  local coverage = require("lib.nvim.docmap.coverage")
  write("docs/TESTS/demo_spec.lua", {
    "local util = require('demo.util')",
    "assert(util.trim('x') ~= nil)",
  })

  local cov_tree = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  coverage.resolve(cov_tree, { root = root, lua_root = "lua" })

  local trim_fn, run_fn
  for _, fn in ipairs(cov_tree.nodes[util].functions) do
    if fn.name == "M.trim" then
      trim_fn = fn
    end
  end
  for _, fn in ipairs(cov_tree.nodes[app].functions) do
    if fn.name == "M.run" then
      run_fn = fn
    end
  end
  ok(trim_fn.tested, "docmap.coverage: a function named in a spec file is tested = true")
  ok(
    not run_fn.tested,
    "docmap.coverage: a function never mentioned in any spec stays tested = false"
  )

  local tested_n, total_n = coverage.summary(cov_tree)
  eq(tested_n, 1, "docmap.coverage: summary counts exactly the one tested function")
  ok(total_n >= 2, "docmap.coverage: summary's total covers every function in the tree")

  local cov_none = scan.scan({ root = root, source = "lua/demo", lua_root = "lua" })
  coverage.resolve(cov_none, { root = root, lua_root = "lua", tests_dir = "no/such/dir" })
  local none_tested = coverage.summary(cov_none)
  eq(
    none_tested,
    0,
    "docmap.coverage: a missing tests_dir leaves every function untested, not an error"
  )

  -- --------------------------------------------------- doccoverage (R4)
  local doccoverage = require("lib.nvim.docmap.doccoverage")
  local doc_ir = make_ir({
    ["a"] = {
      { -- fully documented: summary + matching params
        name = "M.documented",
        signature = "documented(x)",
        summary = "Does the thing.",
        line = 1,
        params = { param("x") },
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
      },
      { -- no summary at all
        name = "M.no_summary",
        signature = "no_summary()",
        summary = "",
        line = 5,
        params = {},
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
      },
      { -- summary present, but a parameter has no matching @param line
        name = "M.bad_params",
        signature = "bad_params(x, y)",
        summary = "Half documented.",
        line = 9,
        params = { param("x") },
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
      },
      { -- @internal: excluded from the total entirely, documented or not
        name = "M.internal_thing",
        signature = "internal_thing()",
        summary = "",
        line = 13,
        params = {},
        returns = {},
        generic = {},
        async = false,
        nodiscard = false,
        see = {},
        overload = {},
        internal = true,
      },
    },
  })

  local doc_documented, doc_total = doccoverage.summary(doc_ir)
  eq(doc_total, 3, "docmap.doccoverage: @internal functions are excluded from the total")
  eq(
    doc_documented,
    1,
    "docmap.doccoverage: only the summary+matching-params function counts as documented"
  )

  local svg = doccoverage.badge_svg(doc_ir)
  ok(svg:match("^<svg"), "docmap.doccoverage: badge_svg produces an <svg> document")
  ok(svg:match("33%%"), "docmap.doccoverage: badge_svg's percentage matches the summary (1/3)")
  ok(svg:match("doc coverage"), "docmap.doccoverage: badge_svg labels itself")

  local empty_documented, empty_total = doccoverage.summary(make_ir({ ["a"] = {} }))
  eq(empty_documented, 0, "docmap.doccoverage: a tree with no functions documents zero")
  eq(empty_total, 0, "docmap.doccoverage: a tree with no functions has zero total")

  -- `M.resolve` stamps `fn.documented` in place — what the Analysis tab's
  -- Documentation panel reads instead of reimplementing is_documented in
  -- JS. Must agree exactly with M.summary's own count over the same IR, or
  -- the panel and the CLI/badge number would quietly disagree.
  doccoverage.resolve(doc_ir)
  local stamped_documented, stamped_total = 0, 0
  for _, id in ipairs(doc_ir.order) do
    for _, fn in ipairs(doc_ir.nodes[id].functions) do
      if not fn.internal then
        stamped_total = stamped_total + 1
      end
      if fn.documented then
        stamped_documented = stamped_documented + 1
      end
    end
  end
  eq(
    stamped_documented,
    doc_documented,
    "docmap.doccoverage: resolve's stamped fn.documented count matches summary's"
  )
  eq(
    stamped_total,
    doc_total,
    "docmap.doccoverage: resolve never stamps documented=true on an @internal function"
  )
  ok(
    (function()
      for _, fn in ipairs(doc_ir.nodes["a"].functions) do
        if fn.name == "M.internal_thing" then
          return fn.documented == false
        end
      end
      return false
    end)(),
    "docmap.doccoverage: an @internal function is always documented = false, never true"
  )

  -- ------------------------------------------------------- history (R11 P1)
  local history = require("lib.nvim.docmap.history")

  ---@param name string
  ---@param line integer
  ---@param line_end integer?
  local function hfn(name, line, line_end)
    return {
      name = name,
      signature = name .. "()",
      summary = "s",
      line = line,
      line_end = line_end,
      params = {},
      returns = {},
      generic = {},
      async = false,
      nodiscard = false,
      see = {},
      overload = {},
    }
  end

  -- parse_diff: the four hunk shapes git actually emits at --unified=0.
  local parsed = history.parse_diff(table.concat({
    "diff --git a/a/init.lua b/a/init.lua",
    "index 1111111..2222222 100644",
    "--- a/a/init.lua",
    "+++ b/a/init.lua",
    "@@ -12,3 +12,4 @@ function M.alpha()",
    "@@ -20 +21 @@ function M.alpha()",
    "@@ -30,0 +32,2 @@ function M.beta()",
    "diff --git a/b/init.lua b/b/init.lua",
    "new file mode 100644",
    "--- /dev/null",
    "+++ b/b/init.lua",
    "@@ -0,0 +1,5 @@",
  }, "\n"))

  eq(#parsed, 2, "docmap.history: parse_diff finds both files")
  eq(parsed[1].new_path, "a/init.lua", "docmap.history: strips git's b/ prefix")
  eq(#parsed[1].old, 2, "docmap.history: a -N,0 hunk contributes no old range")
  eq(parsed[1].old[1].first, 12, "docmap.history: old range start")
  eq(parsed[1].old[1].last, 14, "docmap.history: old range end (start + count - 1)")
  eq(parsed[1].old[2].first, 20, "docmap.history: a missing count means exactly one line")
  eq(parsed[1].old[2].last, 20, "docmap.history: …so first == last")
  eq(parsed[1].new[3].first, 32, "docmap.history: pure insertion keeps its new range")
  eq(parsed[1].new[3].last, 33, "docmap.history: …spanning `count` lines")
  eq(parsed[2].old_path, nil, "docmap.history: /dev/null on the old side means added file")
  eq(parsed[2].new_path, "b/init.lua", "docmap.history: added file still has a new path")

  -- analyze, exact spans: alpha 10-20, beta 30-40, with a real gap between.
  local hist_ir = make_ir({
    ["a"] = { hfn("M.alpha", 10, 20), hfn("M.beta", 30, 40) },
    ["b"] = { hfn("M.caller", 5, 8) },
  }, {
    { kind = "call", from = "b", from_fn = "M.caller", to = "a", to_fn = "M.alpha", line = 6 },
  })

  ---@param hunk string
  ---@param path string?
  local function diff_for(hunk, path)
    path = path or "a/init.lua"
    return table.concat({
      "diff --git a/" .. path .. " b/" .. path,
      "--- a/" .. path,
      "+++ b/" .. path,
      hunk,
    }, "\n")
  end

  local mid = history.analyze(diff_for("@@ -15,2 +15,2 @@"), hist_ir, hist_ir)
  eq(#mid.touched, 1, "docmap.history: a change inside one function touches exactly it")
  eq(mid.touched[1].fn, "M.alpha", "docmap.history: …and names that function")
  eq(mid.approximate, false, "docmap.history: exact line_end needs no approximation")

  -- Both boundaries are inclusive: the `function` line and the `end` line are
  -- part of the function, and an off-by-one either way would silently drop
  -- exactly the single-line signature changes most worth catching.
  eq(
    #history.analyze(diff_for("@@ -10 +10 @@"), hist_ir, hist_ir).touched,
    1,
    "docmap.history: a change on the declaration line counts"
  )
  eq(
    #history.analyze(diff_for("@@ -20 +20 @@"), hist_ir, hist_ir).touched,
    1,
    "docmap.history: a change on the closing `end` line counts"
  )

  local gap = history.analyze(diff_for("@@ -25 +25 @@"), hist_ir, hist_ir)
  eq(#gap.touched, 0, "docmap.history: a change between two functions touches neither")
  eq(gap.unattributed[1], "a/init.lua", "docmap.history: …and is reported as unattributed")

  -- Callers, and the two answers they feed.
  local cs = mid.callers["a#M.alpha"]
  eq(#cs, 1, "docmap.history: the call edge into a touched function is found")
  eq(cs[1].fn, "M.caller", "docmap.history: caller is named by its declared function")
  eq(cs[1].node, "b", "docmap.history: …and by the node it lives in")
  eq(mid.calling_modules[1], "b", "docmap.history: calling_modules is the precise answer")

  -- Degradation: an artifact without line_end (every revision older than the
  -- field itself). Spans fall back to the next function's start, which
  -- over-attributes the gap — and must say so.
  local old_ir = make_ir({ ["a"] = { hfn("M.alpha", 10), hfn("M.beta", 30) } })
  local approx = history.analyze(diff_for("@@ -25 +25 @@"), old_ir, old_ir)
  eq(approx.approximate, true, "docmap.history: a missing line_end is flagged as approximate")
  eq(#approx.touched, 1, "docmap.history: the fallback still attributes the change")
  eq(
    approx.touched[1].fn,
    "M.alpha",
    "docmap.history: …to the preceding function, erring toward over-attribution"
  )

  -- A path the map does not know is reported, not silently dropped.
  local unknown = history.analyze(diff_for("@@ -1 +1 @@", "README.md"), hist_ir, hist_ir)
  eq(#unknown.touched, 0, "docmap.history: an unscanned path touches no function")
  eq(unknown.unattributed[1], "README.md", "docmap.history: …and is listed as unattributed")
  eq(unknown.files[1], "README.md", "docmap.history: every changed path is reported in files")

  -- Missing IRs (a first commit has no parent) degrade to files-only rather
  -- than erroring.
  local no_ir = history.analyze(diff_for("@@ -15 +15 @@"), nil, nil)
  eq(#no_ir.touched, 0, "docmap.history: no IR means no attribution, not a crash")
  eq(#no_ir.files, 1, "docmap.history: …but the changed file is still reported")

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
    -- Every fixture module declares one function, so the diff below has
    -- something to lose when a module is deleted.
    lines[#lines + 1] = "---Runs."
    lines[#lines + 1] = "function M.run()"
    lines[#lines + 1] = "  return 1"
    lines[#lines + 1] = "end"
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

  -- --------------------------------------------------------------- diff
  -- The same tree with one module gone, one function gone and one dependency
  -- made load-time instead of lazy — every section exercised at once.
  local diff = require("lib.nvim.docmap.diff")
  local nothing = diff.compare(gir, gir)
  eq(diff.is_empty(nothing), true, "diff: a map against itself is empty")

  gwrite("lua/g/five/init.lua", {
    "---@module 'g.five'",
    "--- Five.",
    'local _four = require("g.four")',
    "local M = {}",
    "---New.",
    "function M.fresh()",
    "  return 1",
    "end",
    "return M",
  })
  vim.fn.delete(gr .. "/lua/g/two", "rf")
  local after = scan.scan({ root = gr, source = "lua/g", lua_root = "lua" })
  local d = diff.compare(gir, after)

  eq(diff.is_empty(d), false, "diff: a changed tree is not empty")
  eq(d.nodes_added[1], "lua/g/five", "diff: the new module is reported")
  eq(d.nodes_removed[1], "lua/g/two", "diff: and the deleted one")
  eq(d.functions_added[1], "lua/g/five#M.fresh", "diff: functions are keyed like everywhere else")
  eq(d.functions_removed[1], "lua/g/two#M.run", "diff: the deleted module's functions are gone too")
  eq(d.deps_comparable, true, "diff: two current maps are comparable")

  local added_edges, removed_edges = {}, {}
  for _, e in ipairs(d.deps_added) do
    added_edges[e.edge] = true
  end
  for _, e in ipairs(d.deps_removed) do
    removed_edges[e.edge] = true
  end
  ok(added_edges["lua/g/five -> lua/g/four"], "diff: the new dependency is reported")
  ok(removed_edges["lua/g/one -> lua/g/two"], "diff: and the one that vanished with the module")

  -- `three` lost its only dependent when `two` was deleted, so its blast
  -- radius drops. `four` deliberately is *not* asserted on: it gained `five`
  -- and lost `two` in the same change, and the two cancel out exactly — a
  -- reminder that "I changed something near it" is not the same as "its
  -- radius moved".
  local moved = {}
  for _, c in ipairs(d.impact_changed) do
    moved[c.id] = { c.before, c.after }
  end
  ok(moved["lua/g/three"], "diff: a module whose blast radius changed is reported")
  ok(
    moved["lua/g/three"][1] > moved["lua/g/three"][2],
    "diff: with both figures, and this one shrank"
  )

  -- An older artifact is missing this data rather than merely shaped
  -- differently; saying "every dependency in the tree was added" would be
  -- true and useless.
  local ancient = vim.deepcopy(gir)
  ancient.meta.schema = 1
  ancient.edges = {}
  local old_diff = diff.compare(ancient, after)
  eq(old_diff.deps_comparable, false, "diff: a schema-1 map is not comparable on dependencies")
  eq(#old_diff.deps_added, 0, "diff: so no dependency is claimed to be new")
  local rendered = table.concat(diff.render(old_diff, ancient, after, "old"), "\n")
  ok(rendered:find("predates the dependency graph", 1, true), "diff: and the reason is stated")

  vim.fn.delete(gr, "rf")

  -- ------------------------------------------------------ dead-function check
  -- The trap this check is built around, made concrete: a library consists of
  -- functions with no internal caller by design, so it fires in two tiers —
  -- always-on where the statement genuinely holds (file-local, @internal),
  -- opt-in everywhere else.
  local dr = H.tmpfile("_dead")
  local function dwrite(rel, lines)
    local abs = dr .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    local fd = assert(io.open(abs, "w"), "docmap spec: dead-function fixture must be writable")
    fd:write(table.concat(lines, "\n"))
    fd:close()
  end

  dwrite("lua/d/a/init.lua", {
    "---@module 'd.a'",
    "--- A.",
    "local M = {}",
    "---Truly dead: nothing in this file mentions it again.",
    "local function truly_dead()",
    "  return 1",
    "end",
    "---Passed as a value, never called at a call site.",
    "local function as_value()",
    "  return 2",
    "end",
    "---Public, uncalled anywhere, but tagged.",
    "---@internal",
    "function M.internal_unused()",
    "  return 3",
    "end",
    "---Public and uncalled — the always-on tiers must NOT flag this.",
    "function M.public_unused()",
    "  return 4",
    "end",
    -- Declared with `:`, exactly the shape lua/lib/lua/memo/lru.lua uses for
    -- its real public API (Lru:get/Lru:put), which calls.lua cannot resolve
    -- call sites for at all (method-call syntax is invisible to it).
    "---Colon-declared method.",
    "function M:method_dead()",
    "  return 5",
    "end",
    "---Referenced only by another function's @see tag.",
    "function M.only_seen()",
    "  return 6",
    "end",
    "---Documents a relationship to only_seen; itself has no caller.",
    "---@see M.only_seen",
    "function M.seen_by_see()",
    "  return 7",
    "end",
    "---Entry point.",
    "function M.go()",
    "  vim.system({}, as_value)",
    "  return 1",
    "end",
    "return M",
  })

  local dir_ =
    require("lib.nvim.docmap.scan").scan({ root = dr, source = "lua/d", lua_root = "lua" })
  local function dead_messages(dead_code)
    local dopts = { root = dr, source = "lua/d", lua_root = "lua", dead_code = dead_code }
    local out = {}
    for _, f in ipairs(check.run(dir_, dopts)) do
      if f.check == "dead-function" then
        out[f.message:match("^(%S+)")] = f.message
      end
    end
    return out
  end

  local default_dead = dead_messages(false)
  ok(
    default_dead.truly_dead,
    "check.dead-function: a genuinely unreferenced local is flagged by default"
  )
  ok(
    default_dead["M.internal_unused"],
    "check.dead-function: an @internal function with no caller is flagged by default"
  )
  eq(
    default_dead.as_value,
    nil,
    "check.dead-function: a function passed by value to another call is not dead"
  )
  eq(
    default_dead["M.public_unused"],
    nil,
    "check.dead-function: an ordinary public function is NOT flagged without opts.dead_code — a library is exactly this"
  )
  eq(
    default_dead["M:method_dead"],
    nil,
    "check.dead-function: a colon-declared method is not mistaken for a private local"
  )
  eq(
    default_dead.only_seen or default_dead["M.only_seen"],
    nil,
    "check.dead-function: a documented @see TARGET counts as used"
  )

  local opted_in = dead_messages(true)
  ok(
    opted_in["M.public_unused"],
    "check.dead-function: opts.dead_code reaches an ordinary uncalled public function"
  )
  ok(
    opted_in["M:method_dead"],
    "check.dead-function: opts.dead_code reaches an uncalled colon method too"
  )
  eq(
    opted_in.as_value,
    nil,
    "check.dead-function: opts.dead_code still respects local_refs — a callback stays not-dead"
  )
  ok(
    opted_in["M.seen_by_see"],
    "check.dead-function: the function CARRYING the @see tag is not itself excused by it"
  )

  for _, f in ipairs(check.run(dir_, { root = dr, source = "lua/d", lua_root = "lua" })) do
    if f.check == "dead-function" then
      eq(f.severity, "info", "check.dead-function: never above info severity")
    end
  end

  vim.fn.delete(dr, "rf")

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
