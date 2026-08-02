---@module 'lib.nvim.usercmd.composer.check'
--- Pre-flight validation of a verb's routes: does every route's `run` actually
--- resolve, and does its optional `route.check` pass?
---
--- Shaped like `docgen.lua` on purpose — both walk `tree.each_route` over the
--- same route tree that drives dispatch and completion, so neither can drift
--- from real behavior. Where docgen renders that walk as Markdown, this renders
--- it as pass/fail results.
---
--- The value this adds is timing. A route whose `run` is a module path string
--- is required lazily, on first dispatch — so a typo'd or broken module stays
--- invisible until someone runs that exact subcommand, and the failure surfaces
--- as a bare "no runnable handler" with the real reason swallowed. `results()`
--- resolves every route up front and reports the actual error.
---
---   local composer = require("lib.nvim.usercmd.composer")
---   composer.checkhealth("Replace")      -- inside your plugin's health.lua
---   composer.notify_check_all()          -- or a one-shot notification

local tree = require("lib.nvim.usercmd.composer.tree")
local parse = require("lib.nvim.usercmd.composer.parse")
local registry = require("lib.nvim.usercmd.composer.registry")

local M = {}

-- vim.health shim, same shape as lua/lib/health.lua: the report_* spellings
-- are the pre-0.10 names and still exist on some supported versions.
local H = vim.health or {}
local h_start = H.start or H.report_start
local h_ok = H.ok or H.report_ok
local h_error = H.error or H.report_error
local h_info = H.info or H.report_info

--- Check every route of one verb.
---@param root Lib.UserCmd.Composer.Node
---@return Lib.UserCmd.Composer.CheckResult[]
function M.results(root)
  ---@type Lib.UserCmd.Composer.CheckResult[]
  local out = {}

  tree.each_route(root, function(route)
    ---@type Lib.UserCmd.Composer.CheckResult
    local entry = { path = route.path, ok = true }

    local _, err = parse.resolve_run(route.run)
    if err then
      entry.ok, entry.err = false, err
    elseif route.check then
      -- pcall, not a bare call: a route.check that throws is a bug in the
      -- check itself, and must not take down the whole health report with it.
      -- The prefix keeps that case distinguishable from an honest `false, err`.
      local pok, cok, cerr = pcall(route.check)
      if not pok then
        entry.ok, entry.err = false, "check() errored: " .. tostring(cok)
      elseif not cok then
        entry.ok, entry.err = false, cerr or "check() returned false"
      end
    end

    out[#out + 1] = entry
  end)

  return out
end

--- Check every verb registered in this process.
---@return table<string, Lib.UserCmd.Composer.CheckResult[]>
function M.all()
  local out = {}
  for _, handle in ipairs(registry.all()) do
    out[handle:name()] = handle:check()
  end
  return out
end

--- Render one verb's check results through `vim.health`.
---
--- Cannot register itself as a discoverable `:checkhealth <plugin>` target —
--- Neovim finds those by scanning the runtimepath for a real
--- `lua/<plugin>/health.lua` file, which a library cannot create on another
--- plugin's behalf at runtime. Call this FROM your plugin's existing
--- health.lua instead; composer generates the per-route content, you supply
--- the one line that runs it.
---@param name_or_handle string|Lib.UserCmd.Composer.Handle
function M.checkhealth(name_or_handle)
  local handle = type(name_or_handle) == "table" and name_or_handle
    or registry.get(name_or_handle --[[@as string]])
  local name = handle and handle:name() or tostring(name_or_handle)

  h_start(("%s: routes"):format(name))

  if not handle then
    h_error(("verb '%s' is not registered"):format(name), {
      "composer.verb() must run before the health check — check your plugin's setup order.",
    })
    return
  end

  local results = handle:check()
  if #results == 0 then
    -- An empty section would otherwise render as Neovim's generic "no health
    -- info" placeholder, which reads like the check failed to run at all.
    h_info("no routes declared")
    return
  end

  for _, r in ipairs(results) do
    local label = ":" .. name .. (#r.path > 0 and (" " .. table.concat(r.path, " ")) or "")
    if r.ok then
      h_ok(label)
    else
      h_error(label .. " — " .. tostring(r.err))
    end
  end
end

--- Notification-based alternative to `checkhealth`, for a plugin that has no
--- health.lua to hook into: one summary line, plus a line per failing route.
--- Same `results()` data, different presentation — not a second code path.
---@return boolean ok_overall true when every route of every verb passed
function M.notify_check_all()
  local notify = require("lib.nvim.notify").create("[lib.nvim.usercmd.composer]")

  local total, failed, lines = 0, 0, {}
  for name, results in pairs(M.all()) do
    for _, r in ipairs(results) do
      total = total + 1
      if not r.ok then
        failed = failed + 1
        local label = ":" .. name .. (#r.path > 0 and (" " .. table.concat(r.path, " ")) or "")
        lines[#lines + 1] = ("  %s — %s"):format(label, tostring(r.err))
      end
    end
  end

  if total == 0 then
    notify.info("no composer verbs registered")
    return true
  end
  if failed == 0 then
    notify.info(("all %d route(s) OK"):format(total))
    return true
  end

  table.sort(lines)
  notify.error(("%d of %d route(s) failed:\n%s"):format(failed, total, table.concat(lines, "\n")))
  return false
end

return M
