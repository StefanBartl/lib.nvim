-- TESTS/patterns_prototype_spec.lua — lib.lua.patterns.prototype
return function(H)
  local eq, ok = H.eq, H.ok
  local prototype = require("lib.lua.patterns.prototype")

  local tpl = { width = 80, theme = { fg = "white", bg = "black" }, list = { 1, 2 } }
  local base = prototype.new(tpl)

  local c1 = base:clone()
  eq(c1.width, 80, "clone has the template values")
  c1.theme.fg = "red"
  c1.list[1] = 99
  eq(base:clone().theme.fg, "white", "a clone does not alias nested tables")
  eq(base:clone().list[1], 1, "nor arrays")

  tpl.width = 1
  eq(base:clone().width, 80, "the template was copied at construction")

  local dark = base:clone({ theme = { bg = "blue" }, extra = true })
  eq(dark.theme.bg, "blue", "overrides merge into nested tables")
  eq(dark.theme.fg, "white", "unrelated nested keys survive")
  eq(dark.extra, true, "new keys are added")

  local cyc = { name = "loop" }
  cyc.self = cyc
  local copy = prototype.deepcopy(cyc)
  ok(copy ~= cyc and copy.self == copy, "deepcopy keeps cycles intact")

  local mt = { __index = {
    hi = function()
      return "hi"
    end,
  } }
  local with_mt = prototype.deepcopy(setmetatable({}, mt))
  eq(with_mt.hi(), "hi", "metatables are kept")
  ok(not pcall(prototype.new, 5), "template must be a table")
end
