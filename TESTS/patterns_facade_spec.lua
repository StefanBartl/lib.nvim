-- TESTS/patterns_facade_spec.lua — lib.lua.patterns.facade
return function(H)
  local eq, ok = H.eq, H.ok
  local facade = require("lib.lua.patterns.facade")

  local loads = 0
  package.preload["facade_spec.parser"] = function()
    loads = loads + 1
    return {
      parse = function(s)
        return "parsed:" .. s
      end,
    }
  end

  local api = facade.new({
    parse = "facade_spec.parser:parse",
    parser = "facade_spec.parser",
    version = function()
      return "1.0"
    end,
  })

  eq(loads, 0, "nothing is required up front")
  eq(table.concat(api.names(), ","), "parse,parser,version", "names are the declared entries")
  eq(#api.loaded(), 0, "nothing resolved yet")

  eq(api.parse("x"), "parsed:x", "module:function entry resolves the function")
  eq(loads, 1, "the module was required on first use")
  ok(api.parser.parse ~= nil, "a plain module path resolves the module table")
  eq(loads, 1, "the module is not loaded twice")
  eq(api.version(), "1.0", "function entries are returned as they are")
  eq(table.concat(api.loaded(), ","), "parse,parser,version", "loaded lists resolved entries")
  eq(api.unknown, nil, "unknown names are nil")

  ok(not pcall(facade.new, { names = "x" }), "reserved entry names raise")

  package.preload["facade_spec.parser"] = nil
  package.loaded["facade_spec.parser"] = nil
end
