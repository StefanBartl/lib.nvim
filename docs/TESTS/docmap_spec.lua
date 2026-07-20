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
    "--- local ok = M.old_thing(\"x\")",
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
    if f.name == "M.old_thing" then old_thing = f end
    if f.name == "M.new_thing" then new_thing = f end
    if f.name == "bare_helper" then bare = f end
  end

  ok(old_thing, "docmap.functions: M.old_thing found")
  eq(old_thing.signature, "M.old_thing(x, opts)", "docmap.functions: signature is the qualified name plus params")
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
  ok(old_thing.example and old_thing.example:match("assert%(ok%)"),
    "docmap.functions: @example block captured across multiple lines")
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
        id = id, kind = "module", name = id, path = id, source = id .. "/init.lua",
        module = id:gsub("/", "."), summary = "x", body = "", readme = "x.md", types = {},
        export = "table", parent = nil, depth = 0, children = {}, functions = fns_,
      }
      order[#order + 1] = id
    end
    table.sort(order)
    return { meta = { title = "t", source = "lua", types_dir = "@types", branch = "main", schema = 1,
      counts = { module = #order, namespace = 0, file = 0 } },
      root = order[1], order = order, nodes = nodes, edges = {} }
  end

  local ir = make_ir({
    ["a"] = { {
      name = "M.foo", signature = "foo(x, y)", summary = "", line = 1,
      params = { { name = "x", type = "string", optional = false, desc = "" } },
      returns = {}, generic = {}, deprecated = nil, async = false, nodiscard = false,
      see = { "b.bar", "nowhere.real" }, overload = {}, example = nil, since = nil,
    } },
    ["b"] = { {
      name = "M.bar", signature = "bar()", summary = "", line = 1,
      params = {}, returns = {}, generic = {}, deprecated = nil, async = false, nodiscard = false,
      see = {}, overload = {}, example = nil, since = nil,
    } },
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
  ok(not (function()
    for _, f in ipairs(findings) do
      if f.check == "dead-see-target" and f.message:match("b%.bar") then return true end
    end
    return false
  end)(), "docmap.check: dead-see-target does NOT fire for 'b.bar', which resolves via module+bare-name")
  ok(has_undoc_param, "docmap.check: undocumented-param fires when signature has more params than @param lines")
end
