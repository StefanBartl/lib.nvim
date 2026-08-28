-- TESTS/dev_duplicates_spec.lua — lib.nvim.dev.duplicates

return function(H)
  local eq, ok = H.eq, H.ok

  local duplicates = require("lib.nvim.dev.duplicates")

  ---@param path string
  ---@param content string
  local function write(path, content)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local fd = assert(io.open(path, "w"))
    fd:write(content)
    fd:close()
  end

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  -- Same body (modulo a comment and whitespace) in two repos: a real hit.
  write(
    root .. "/repo-a.nvim/lua/repo_a/init.lua",
    table.concat({
      "local function shared_helper(x, y)",
      "  -- a comment that should be ignored",
      "  local total = x + y",
      "  if total > 10 then",
      "    return total * 2",
      "  end",
      "  return total",
      "end",
      "",
      "function M.only_in_a() return 1 end",
    }, "\n")
  )
  write(
    root .. "/repo-b.nvim/lua/repo_b/util.lua",
    table.concat({
      "local function shared_helper(x, y)",
      "  local total = x + y",
      "  if total > 10 then",
      "    return total * 2",
      "  end",
      "  return total",
      "end",
    }, "\n")
  )
  -- A third repo with its own, unrelated function: must not join the group.
  write(
    root .. "/repo-c.nvim/lua/repo_c/other.lua",
    table.concat({
      "local function unique_thing()",
      "  local a = 1",
      "  local b = 2",
      "  local c = 3",
      "  return a + b + c",
      "end",
    }, "\n")
  )
  -- lib.nvim's own directory name is always excluded, even if present.
  write(root .. "/lib.nvim/lua/lib/init.lua", "local function shared_helper(x, y)\nend\n")

  local groups = duplicates.scan(root)
  eq(#groups, 1, "exactly one duplicate group")
  local g = groups[1]
  eq(#g.repos, 2, "the group spans exactly two repos")
  eq(g.repos[1], "repo-a.nvim", "repos sorted, repo-a first")
  eq(g.repos[2], "repo-b.nvim", "repos sorted, repo-b second")
  for _, r in ipairs(g.repos) do
    ok(r ~= "lib.nvim", "lib.nvim never appears in a group even when it has the same body")
  end

  -- only_in_a / unique_thing appear once each -- never grouped.
  for _, h in ipairs(g.hits) do
    ok(h.name ~= "only_in_a" and h.name ~= "unique_thing", "single-repo functions are not hits")
  end

  -- A root with no sibling repos underneath finds nothing (not an error).
  local lone_root = vim.fn.tempname()
  vim.fn.mkdir(lone_root .. "/solo.nvim/lua/solo", "p")
  write(lone_root .. "/solo.nvim/lua/solo/init.lua", "local function only_here() return 1 end\n")
  eq(#duplicates.scan(lone_root), 0, "no sibling repos to compare against -> no groups")

  local lines = duplicates.lines(root)
  ok(#lines > 0, "lines() renders something")
end
