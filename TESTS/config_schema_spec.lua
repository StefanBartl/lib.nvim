-- TESTS/config_schema_spec.lua -- lib.lua.config.schema
--
-- Every spec form, the typo hints, "never changes its input", and infer():
-- a record schema built out of a DEFAULTS table plus the exceptions a default
-- value can not say.

return function(H)
  local eq, ok = H.eq, H.ok
  local schema = require("lib.lua.config.schema")

  ---Check one value; returns kept, issues.
  local function one(value, spec)
    local issues = {}
    local kept = schema.check(value, spec, "opt", issues)
    return kept, issues
  end

  local function issues_of(value, spec)
    local _, found = one(value, spec)
    return found
  end

  local function has(issues, needle)
    for _, line in ipairs(issues) do
      if line:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  eq(schema.describe_got(5), "5", "describe_got: a number as it is")
  eq(schema.describe_got(false), "false", "describe_got: a boolean as it is")
  eq(schema.describe_got("x"), '"x"', "describe_got: a string quoted")
  eq(schema.describe_got({}), "table", "describe_got: anything else by its type")

  -- ------------------------------------------------------------------ plain types
  local kept, issues = one(5, "number")
  eq(kept, 5, "number: accepted")
  eq(#issues, 0, "number: no issue")
  kept, issues = one("x", "number")
  eq(kept, nil, "number: a string is rejected")
  ok(
    has(issues, "option 'opt' must be a number, got \"x\" -- using the default"),
    "number: message " .. issues[1]
  )
  kept = one(false, "boolean")
  eq(kept, false, "boolean: false is a value, not a rejection")
  kept = one(function() end, "function")
  ok(type(kept) == "function", "function: accepted")

  -- ---------------------------------------------------------------------- unions
  kept = one(false, "string|false")
  eq(kept, false, "union: the literal false matches")
  kept = one("a", "string|false")
  eq(kept, "a", "union: the string matches")
  kept, issues = one(true, "string|false")
  eq(kept, nil, "union: true matches neither")
  ok(has(issues, "must be a string or false, got true"), "union: label names both " .. issues[1])
  kept = one(false, "string")
  eq(kept, nil, "union: without the false token, false is rejected")
  kept = one({}, "table|false")
  ok(type(kept) == "table", "union: table|false takes a table")

  -- ---------------------------------------------------------------------- bounds
  kept = one(3, { "number", min = 1, max = 5 })
  eq(kept, 3, "bounds: inside")
  kept = one(1, { "number", min = 1, max = 5 })
  eq(kept, 1, "bounds: min is inclusive")
  kept = one(5, { "number", min = 1, max = 5 })
  eq(kept, 5, "bounds: max is inclusive")
  kept, issues = one(0, { "number", min = 1, max = 5 })
  eq(kept, nil, "bounds: below min")
  ok(has(issues, "between 1 and 5"), "bounds: message " .. issues[1])
  eq(#issues_of(9, { "number", min = 1 }), 0, "bounds: only a min leaves the top open")
  ok(has(issues_of(0, { "number", min = 1 }), ">= 1"), "bounds: one-sided message")
  ok(has(issues_of(9, { "number", max = 5 }), "<= 5"), "bounds: upper-only message")
  kept, issues = one(0 / 0, "number")
  eq(kept, nil, "bounds: NaN never passes")
  ok(has(issues, "finite number"), "bounds: NaN message " .. issues[1])
  kept = one(math.huge, "number")
  eq(kept, nil, "bounds: +inf never passes")
  kept = one(-math.huge, { "number", min = -5 })
  eq(kept, nil, "bounds: -inf never passes")

  -- ------------------------------------------------------------------------ enum
  kept = one("b", { "string", enum = { "a", "b" } })
  eq(kept, "b", "enum: member accepted")
  kept, issues = one("c", { "string", enum = { "a", "b" } })
  eq(kept, nil, "enum: non-member rejected")
  ok(has(issues, 'must be one of "a", "b", got "c"'), "enum: message " .. issues[1])
  kept = one(false, { "string|false", enum = { "a" } })
  eq(kept, false, "enum: applies to string values only")

  -- ---------------------------------------------------------------------- keymap
  eq(one("<C-x>", "keymap"), "<C-x>", "keymap: a key")
  eq(one(false, "keymap"), false, "keymap: false unmaps")
  local list = { "a", "b" }
  kept = one(list, "keymap")
  eq(#kept, 2, "keymap: a list of keys")
  ok(kept ~= list, "keymap: the list is copied")
  kept, issues = one({ "a", 5 }, "keymap")
  eq(kept, nil, "keymap: a non-string element rejects the list")
  ok(has(issues, "option 'opt.2' must be a string, got 5"), "keymap: element message " .. issues[1])
  kept, issues = one(5, "keymap")
  eq(kept, nil, "keymap: a number is rejected")
  ok(has(issues, "a string, a list of strings or false"), "keymap: message " .. issues[1])

  -- ---------------------------------------------------------------------- records
  local fields = {
    width = { "number", min = 1 },
    title = "string",
    nested = { "table", fields = { on = "boolean" } },
  }
  local body = { width = 10, title = "t", nested = { on = true } }
  issues = {}
  local clean = schema.check_record(body, fields, "", issues)
  eq(#issues, 0, "record: a valid body reports nothing")
  eq(clean.nested.on, true, "record: nested values are kept")
  ok(clean ~= body and clean.nested ~= body.nested, "record: the result is a new table, nested too")

  issues = {}
  clean = schema.check_record(
    { width = 0, title = 5, nested = { on = "yes", extra = 1 } },
    fields,
    "cfg",
    issues
  )
  eq(clean.width, nil, "record: a rejected value is left out")
  eq(clean.title, nil, "record: ...each one")
  ok(clean.nested ~= nil and clean.nested.on == nil, "record: a nested record keeps what passed")
  eq(#issues, 4, "record: one line per problem: " .. table.concat(issues, " | "))
  ok(has(issues, "option 'cfg.width'"), "record: the path is dotted from the prefix")
  ok(has(issues, "option 'cfg.nested.on' must be a boolean"), "record: ...and nested")
  ok(
    has(issues, "unknown option 'cfg.nested.extra'"),
    "record: an unknown key inside a nested record"
  )

  local again = {}
  schema.check_record(
    { width = 0, title = 5, nested = { on = "yes", extra = 1 } },
    fields,
    "cfg",
    again
  )
  eq(
    table.concat(again, "|"),
    table.concat(issues, "|"),
    "record: the same input reports in the same order"
  )

  -- many unknown keys come back in alphabetical order, whatever the hash order is
  local many = {}
  for n = 12, 1, -1 do
    many[("zz%02d"):format(n)] = n
  end
  issues = {}
  schema.check_record(many, {}, "", issues)
  local names = {}
  for _, line in ipairs(issues) do
    names[#names + 1] = line:match("'(zz%d+)'")
  end
  local sorted = vim.deepcopy(names)
  table.sort(sorted)
  eq(
    table.concat(names, ","),
    table.concat(sorted, ","),
    "record: issues are reported in key order"
  )
  eq(#names, 12, "record: all twelve unknown keys are reported")

  -- the body is never changed
  local input = { width = 0, bogus = 1, nested = { extra = 1 } }
  schema.check_record(input, fields, "", {})
  eq(input.bogus, 1, "record: an unknown key stays in the caller's table")
  eq(input.width, 0, "record: a rejected value stays in the caller's table")
  eq(input.nested.extra, 1, "record: nested too")

  -- ---------------------------------------------------------------------- typos
  issues = {}
  schema.check_record({ widht = 3 }, fields, "", issues)
  eq(
    issues[1],
    "unknown option 'widht' (did you mean 'width'?)",
    "typo: hint at the root, no leading dot"
  )
  issues = {}
  schema.check_record({ zzzzzzzz = 3 }, fields, "a.b", issues)
  eq(issues[1], "unknown option 'a.b.zzzzzzzz'", "typo: nothing near enough, no hint")
  eq(
    schema.describe_unknown("titel", { title = true }, "x."),
    "unknown option 'x.titel' (did you mean 'x.title'?)",
    "typo: prefix on both names"
  )

  -- ------------------------------------------------------------------------- of
  kept = one({ "a", "b" }, { "table", of = "string" })
  eq(#kept, 2, "of: every element matches")
  kept, issues = one({ "a", 5 }, { "table", of = "string" })
  eq(kept, nil, "of: one bad element drops the whole table")
  ok(has(issues, "option 'opt.2' must be a string"), "of: the element is named " .. issues[1])
  kept = one({ k = "v", j = "w" }, { "table", of = "string" })
  eq(kept.j, "w", "of: an open map")
  kept = one({}, { "table", of = "string" })
  eq(next(kept), nil, "of: empty is fine")
  kept = one({ { n = 1 }, { n = 2 } }, { "table", of = { "table", fields = { n = "number" } } })
  eq(kept[2].n, 2, "of: records inside a list")

  -- ------------------------------------------------------------------------ infer
  local defaults = {
    width = 80,
    title = "t",
    enabled = true,
    border = false,
    cb = function() end,
    groups = { "a", "b" },
    free = {},
    ui = { sizes = { w = 1, h = 2 }, accent = "red" },
  }
  local inferred = schema.infer(defaults)
  issues = {}
  schema.check(defaults, inferred, "", issues)
  eq(#issues, 0, "infer: the defaults pass their own schema: " .. table.concat(issues, " | "))

  issues = {}
  schema.check({ width = "wide" }, inferred, "", issues)
  ok(has(issues, "option 'width' must be a number"), "infer: a number default means a number")
  issues = {}
  schema.check({ ui = { sizes = { w = "x" } } }, inferred, "", issues)
  ok(has(issues, "option 'ui.sizes.w' must be a number"), "infer: nested maps are records")
  issues = {}
  schema.check({ ui = { sizess = {} } }, inferred, "", issues)
  ok(
    has(issues, "unknown option 'ui.sizess' (did you mean 'ui.sizes'?)"),
    "infer: a nested record is closed"
  )
  issues = {}
  schema.check({ groups = { { "x", "y" } }, free = { anything = { 1, 2 } } }, inferred, "", issues)
  eq(#issues, 0, "infer: a list or {} default takes any table")
  issues = {}
  schema.check({ groups = "x" }, inferred, "", issues)
  ok(has(issues, "option 'groups' must be a table"), "infer: ...but not a string")
  issues = {}
  schema.check({ border = "rounded" }, inferred, "", issues)
  ok(
    has(issues, "option 'border' must be a boolean"),
    "infer: a false default is a boolean (needs an exception for a string)"
  )

  local excepted = schema.infer(defaults, {
    border = "string|false",
    ["ui.accent"] = { "string", enum = { "red", "blue" } },
    ["ui.extra"] = "number",
    telemetry = "table",
    free = { "table", of = "string" },
  })
  issues = {}
  schema.check(
    { border = "rounded", ui = { accent = "blue", extra = 3 }, telemetry = {}, free = { a = "b" } },
    excepted,
    "",
    issues
  )
  eq(
    #issues,
    0,
    "infer: exceptions widen a default, add a key inside a record and add a root key: "
      .. table.concat(issues, " | ")
  )
  issues = {}
  schema.check({ ui = { accent = "green" } }, excepted, "", issues)
  ok(
    has(issues, "option 'ui.accent' must be one of"),
    "infer: an exception wins over the inferred type"
  )
  issues = {}
  schema.check({ free = { a = 1 } }, excepted, "", issues)
  ok(has(issues, "option 'free.a' must be a string"), "infer: an exception replaces a whole branch")

  local bad_ok, bad_err = pcall(schema.infer, defaults, { ["width.deep"] = "number" })
  ok(
    not bad_ok and tostring(bad_err):find("width", 1, true) ~= nil,
    "infer: an exception below a scalar is an error"
  )
  local free_ok = pcall(schema.infer, defaults, { ["free.deep"] = "number" })
  ok(not free_ok, "infer: an exception below an open table is an error")

  -- infer() builds new specs; the defaults it was given stay as they were
  eq(defaults.width, 80, "infer: the defaults are not touched")
  local first = schema.infer(defaults, { border = "string|false" })
  local second = schema.infer(defaults)
  ok(
    first.fields.border ~= second.fields.border,
    "infer: a second call does not inherit the first one's exceptions"
  )
end
