-- TESTS/normalize_switch_group_spec.lua — lib.nvim.normalize.normalize_switch_group (REL-20)

return function(H)
  local ok = H.ok

  ---@param a any
  ---@param b any
  ---@param msg string
  local function eq(a, b, msg)
    ok(vim.deep_equal(a, b), msg .. ": got " .. vim.inspect(a))
  end

  local normalize = require("lib.nvim.normalize")
  local f = normalize.normalize_switch_group

  eq(f(false), { enable = false }, "false -> { enable = false }")
  eq(f(true), {}, "true -> {} (the defaults decide)")
  eq(f(false, "preset"), { preset = false }, "a legacy switch name is honoured")
  eq(f(true, "preset"), {}, "true stays {} for any switch name")

  eq(f(nil), nil, "nil -> nil")
  eq(f("no"), nil, "a string -> nil")
  eq(f(0), nil, "a number -> nil")
  eq(f(function() end), nil, "a function -> nil")

  local input = { enable = true, keys = { save = "<leader>s" } }
  local out = f(input)
  eq(out, input, "a table keeps its content")
  ok(out ~= input, "a table is copied")
  out.keys.save = "x"
  eq(input.keys.save, "<leader>s", "the copy is deep: the caller's input is not changed")

  eq(f({}), {}, "an empty table stays empty")
end
