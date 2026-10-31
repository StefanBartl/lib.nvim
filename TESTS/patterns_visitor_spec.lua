-- TESTS/patterns_visitor_spec.lua — lib.lua.patterns.visitor
return function(H)
  local eq, ok = H.eq, H.ok
  local visitor = require("lib.lua.patterns.visitor")

  local tree = {
    type = "doc",
    children = {
      { type = "heading", text = "Title" },
      {
        type = "list",
        children = { { type = "item", text = "one" }, { type = "item", text = "two" } },
      },
      { type = "para", text = "Body" },
    },
  }

  local describe = visitor.new({
    heading = function(n)
      return "# " .. n.text
    end,
    para = function(n, prefix)
      return (prefix or "") .. n.text
    end,
  }, {
    default = function(n)
      return "<" .. n.type .. ">"
    end,
  })
  eq(describe(tree.children[1]), "# Title", "handler by kind")
  eq(describe(tree.children[3], "> "), "> Body", "extra arguments")
  eq(describe(tree), "<doc>", "default handles other kinds")

  local strict = visitor.new({ a = function() end })
  ok(not pcall(strict, { type = "b" }), "no handler and no default raises")

  local by_kind = visitor.new({
    x = function()
      return "x!"
    end,
  }, {
    kind = function(n)
      return n.kind
    end,
  })
  eq(by_kind({ kind = "x" }), "x!", "custom kind function")

  local seen = {}
  visitor.walk(tree, function(n)
    return n.children
  end, function(n, depth)
    seen[#seen + 1] = depth .. n.type
  end)
  eq(table.concat(seen, ","), "0doc,1heading,1list,2item,2item,1para", "pre-order with depth")

  seen = {}
  visitor.walk(tree, function(n)
    return n.children
  end, function(n)
    seen[#seen + 1] = n.type
    if n.type == "list" then
      return false
    end
  end)
  eq(table.concat(seen, ","), "doc,heading,list,para", "returning false skips the children")
end
