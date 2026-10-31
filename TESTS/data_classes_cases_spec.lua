-- TESTS/data_classes_cases_spec.lua — lib.nvim.data_classes against the shared case list of tasks-desktop
--
-- tasks-desktop keeps one list of `areas.json` cases (ui/web/classes-cases.mjs) that its Rust hub (classes.rs) and its
-- web reader must answer alike; ui/web/classes-cases-dump.mjs prints it as JSON. This spec holds the Lua reader to the
-- same list, so a case added there, or a change of classes.rs the list follows, reaches this reader too. It needs a
-- checkout of tasks-desktop (`TASKS_DESKTOP_DIR`, else a sibling of this repo) and `node`; without them it says it
-- was skipped (lib.nvim's CI has neither).

return function(H)
  local eq, ok = H.eq, H.ok
  local dc = require("lib.nvim.data_classes")

  local dir = vim.env.TASKS_DESKTOP_DIR
  if dir == nil or dir == "" then
    dir = vim.fs.joinpath(vim.fs.dirname(vim.fn.getcwd()), "tasks-desktop")
  end
  local dump = vim.fs.joinpath(dir, "ui", "web", "classes-cases-dump.mjs")
  if vim.fn.filereadable(dump) == 0 then
    H.skipped("data_classes shared cases", "no tasks-desktop checkout at " .. dir)
    return
  end
  if vim.fn.executable("node") == 0 then
    H.skipped("data_classes shared cases", "node is not on PATH")
    return
  end

  local res = vim
    .system({ "node", "web/classes-cases-dump.mjs" }, { cwd = vim.fs.joinpath(dir, "ui"), text = false })
    :wait(60000)
  eq(res.code, 0, "the dump ran: " .. tostring(res.stderr))
  local cases = vim.json.decode(res.stdout)
  ok(type(cases) == "table" and #cases > 100, "the dump has the cases")

  local failed = {}
  for _, case in ipairs(cases) do
    local text = case.hex:gsub("%x%x", function(pair)
      return string.char(tonumber(pair, 16))
    end)
    local classes = dc.parse(text)
    if case.refused then
      if classes.problem == nil then
        failed[#failed + 1] = case.name .. ": not refused"
      end
    elseif classes.problem ~= nil then
      failed[#failed + 1] = ("%s: refused (%s)"):format(case.name, classes.problem)
    else
      for area, want in pairs(case.shows) do
        local got = classes:shown(area)
        if got ~= want then
          failed[#failed + 1] = ("%s: %s is %s, not %s"):format(case.name, area, got, want)
        end
      end
    end
    -- a file that is refused releases nothing
    if classes.problem ~= nil then
      for area in pairs(case.shows) do
        if classes:shown(area) ~= "unclassified" then
          failed[#failed + 1] = case.name .. ": refused but releases " .. area
        end
      end
    end
  end
  eq(#failed, 0, table.concat(failed, "\n      "))
end
