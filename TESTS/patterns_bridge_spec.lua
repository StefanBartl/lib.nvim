-- TESTS/patterns_bridge_spec.lua — lib.lua.patterns.bridge
return function(H)
  local eq, ok = H.eq, H.ok
  local bridge = require("lib.lua.patterns.bridge")

  local report = {
    title = function(out, text)
      out.line(text)
      out.line(("="):rep(#text))
    end,
    count = function(out, n)
      out.line("n=" .. n)
      return n
    end,
  }

  local function sink()
    local lines = {}
    return {
      lines = lines,
      line = function(s)
        lines[#lines + 1] = s
      end,
    }
  end

  local a, b = sink(), sink()
  local ra = bridge.new(report, a, { "line" })
  local rb = bridge.new(report, b, { "line" })
  ra.title("Hi")
  eq(table.concat(a.lines, "|"), "Hi|==", "abstraction runs against implementor A")
  eq(#b.lines, 0, "implementor B is untouched")
  eq(rb.count(3), 3, "return values pass through")
  eq(b.lines[1], "n=3", "same abstraction, other implementor")

  ok(not pcall(bridge.new, report, {}, { "line" }), "missing primitive raises at construction")
  ok(pcall(bridge.new, report, {}), "no required list: nothing checked")
end
