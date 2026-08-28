-- TESTS/bindings_audit_spec.lua — lib.nvim.bindings.audit

return function(H)
  local eq, ok = H.eq, H.ok

  local usercmd = require("lib.nvim.bindings.usercmd")
  local keymap = require("lib.nvim.bindings.keymap")
  local audit = require("lib.nvim.bindings.audit")

  usercmd.create("AuditSpecCmd", function() end, { desc = "audit spec test command" })
  keymap.register("auditspec", {
    prefix = "<Plug>(auditspec-",
    actions = {
      -- name/desc chosen so the word-overlap heuristic in has_route_match()
      -- has nothing to latch onto against AuditSpecCmd's own name/desc.
      frobnicate = {
        default = "<Plug>(auditspec-frobnicate)",
        rhs = function() end,
        desc = "frobnicate the widget",
      },
    },
  })

  -- ------------------------------------------------------- keymap_actions

  local actions = audit.keymap_actions(nil)
  local found_action
  for _, a in ipairs(actions) do
    if a.surface == "auditspec" and a.name == "frobnicate" then
      found_action = a
    end
  end
  ok(found_action, "keymap_actions() lists auditspec.frobnicate")
  eq(found_action.lhs, "<Plug>(auditspec-frobnicate)", "keymap_actions() keeps the bound lhs")

  -- ------------------------------------------------------ command_routes

  local routes = audit.command_routes(nil)
  local found_route = false
  for _, r in ipairs(routes) do
    if r.name == "AuditSpecCmd" then
      found_route = true
      eq(r.path, "(plain)", "a plain usercmd.create() is reported as (plain)")
    end
  end
  ok(found_route, "command_routes() lists AuditSpecCmd")

  -- ------------------------------------------------------------- gaps

  local gaps = audit.gaps(nil)
  local gap_found = false
  for _, g in ipairs(gaps) do
    if g.surface == "auditspec" and g.name == "frobnicate" then
      gap_found = true
    end
  end
  ok(gap_found, "an action with no name/word overlap in any route is a gap")

  -- A route whose own name contains the action's name is not a gap.
  usercmd.create("FrobnicateNow", function() end, { desc = "does the thing" })
  local gaps_after = audit.gaps(nil)
  local still_a_gap = false
  for _, g in ipairs(gaps_after) do
    if g.surface == "auditspec" and g.name == "frobnicate" then
      still_a_gap = true
    end
  end
  ok(not still_a_gap, "a route name containing the action name clears the gap")

  -- ------------------------------------------------------- root scoping

  -- lib.nvim's own repo root: `keymap_actions(root)` resolves the plugin
  -- name from `root/lua/*` (here: "lib"), so scoping to this repo's own
  -- root must NOT include "auditspec" — that name was registered directly
  -- by this spec, not by anything under lib.nvim's own `lua/lib/`.
  local self_root = vim.fn.getcwd()
  local scoped = audit.keymap_actions(self_root)
  local leaked = false
  for _, a in ipairs(scoped) do
    if a.surface == "auditspec" then
      leaked = true
    end
  end
  ok(not leaked, "scoping to lib.nvim's own root excludes actions registered under other names")

  -- ------------------------------------------------------------- lines

  local lines = audit.lines(nil)
  ok(#lines > 0, "lines() renders something")
  local gap_lines = audit.gap_lines(nil)
  ok(#gap_lines > 0, "gap_lines() renders something")
end
