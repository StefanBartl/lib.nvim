-- TESTS/strings_case_style_spec.lua — lib.lua.strings.case: identifier_style / apply_style
-- (extracted from replacer.nvim's casing module; the cases are the behaviour that module had)

return function(H)
  local eq = H.eq
  local strings = require("lib.lua.strings")

  -- detection
  local detect = {
    { "foo", "lower" },
    { "FOO", "upper" },
    { "Foo", "title" },
    { "fooBar", "camel" },
    { "FooBar", "pascal" },
    { "foo_bar", "lower" },
    { "FOO_BAR", "upper" },
    { "Foo_Bar", "pascal" },
    { "foo_Bar", "camel" },
    { "foo-Bar", "camel" },
    { "foo2Bar", "title" }, -- a digit before the capital is no word boundary (as in replacer.nvim before the extraction)
    { "HTTPServer", "title" }, -- no lower->upper boundary inside: a single word to this function
    { "x", "lower" },
    { "X", "upper" },
  }
  for _, c in ipairs(detect) do
    eq(strings.identifier_style(c[1]), c[2], "identifier_style(" .. c[1] .. ")")
  end
  eq(strings.identifier_style(""), nil, "identifier_style: empty text")
  eq(strings.identifier_style(nil), nil, "identifier_style: nil")
  eq(strings.identifier_style("123_456"), nil, "identifier_style: no letter to judge")

  -- application
  local apply = {
    { "bar", "lower", "bar" },
    { "Bar", "lower", "bar" },
    { "bar", "upper", "BAR" },
    { "bar", "title", "Bar" },
    { "BAR", "title", "Bar" },
    { "baz_qux", "camel", "bazQux" },
    { "baz_qux", "pascal", "BazQux" },
    { "BazQux", "camel", "bazQux" },
    { "baz-qux", "pascal", "BazQux" },
    { "single", "camel", "single" },
    { "single", "pascal", "Single" },
  }
  for _, c in ipairs(apply) do
    eq(strings.apply_style(c[1], c[2]), c[3], ("apply_style(%s, %s)"):format(c[1], c[2]))
  end
  eq(strings.apply_style("bar", nil), "bar", "apply_style: no style leaves the text")
  eq(strings.apply_style("bar", "nonsense"), "bar", "apply_style: unknown style leaves the text")
  eq(strings.apply_style("", "upper"), "", "apply_style: empty text")
  eq(strings.apply_style(nil, "upper"), "", "apply_style: nil text gives empty string")
  eq(strings.apply_style("__", "camel"), "__", "apply_style: no words, text unchanged")

  -- non-ASCII letters travel inside their word (case itself stays ASCII only); punctuation separates words
  local function u(code)
    return vim.fn.nr2char(code)
  end
  local gross = "gr" .. u(246) .. u(223) .. "e" -- "grosse" with o-umlaut and sharp s
  eq(
    strings.apply_style(gross .. "_x", "camel"),
    gross .. "X",
    "apply_style: a non-ASCII letter is kept (camel)"
  )
  eq(
    strings.apply_style(gross .. "_x", "pascal"),
    gross:sub(1, 1):upper() .. gross:sub(2) .. "X",
    "apply_style: ... (pascal)"
  )
  eq(
    strings.apply_style(u(252) .. "ber_foo", "pascal"),
    u(252) .. "berFoo",
    "apply_style: a leading non-ASCII letter is not capitalised, not damaged"
  )
  local nihon = u(26085) .. u(26412)
  eq(
    strings.apply_style(nihon .. "_foo", "camel"),
    nihon .. "Foo",
    "apply_style: CJK is kept as a word"
  )
  eq(
    strings.identifier_style(gross .. "X"),
    "camel",
    "identifier_style: a non-ASCII word then a capital is camel"
  )
  eq(
    strings.apply_style(u(201) .. "A", "lower"),
    u(201) .. "a",
    "apply_style: lower() is ASCII only, the other letter is kept intact"
  )
  eq(
    strings.apply_style("foo.bar", "camel"),
    "fooBar",
    "apply_style: punctuation separates words and is dropped"
  )

  -- the use case: one replacement follows the casing of every match
  eq(strings.apply_style("bar", strings.identifier_style("FOO")), "BAR", "match FOO -> BAR")
  eq(strings.apply_style("bar", strings.identifier_style("Foo")), "Bar", "match Foo -> Bar")
  eq(
    strings.apply_style("baz_qux", strings.identifier_style("fooBar")),
    "bazQux",
    "match fooBar -> bazQux"
  )
end
