---@module 'lib.nvim.deps.view'
--- Render a plugin's declared external tools — with each tool's `why`, its
--- status on this host, and what would install it — into buffer lines, and
--- show them in a named scratch split.
---
--- `lines()` is pure and does the whole job; `show()` only puts its output on
--- screen. Split that way because the interesting part (does a missing
--- required tool actually get flagged, does a low-effort `why` get called
--- out) is worth asserting on directly, and a function that opens a window
--- isn't.

local pm = require("lib.nvim.deps.pm")
local install = require("lib.nvim.deps.install")

local M = {}

--- A `why` this short says nothing a bare binary name didn't already say.
--- Flagged rather than rejected: the parser already enforces that `why`
--- exists and is non-empty (see `lib.nvim.deps.spec`), but "useful" isn't
--- something validation can decide — so this is a visible nudge in the one
--- place a plugin author is most likely to look, not a gate.
local WHY_TOO_SHORT = 20

---Render the report for one plugin's parsed spec.
---@param plugin_name string
---@param result Lib.Deps.ParseResult
---@param opts? { manager?: Lib.Deps.Manager }
---@return string[] lines
function M.lines(plugin_name, result, opts)
  local plan = install.plan(result.tools, opts)
  local out = {}

  local function add(s)
    out[#out + 1] = s
  end

  add("# " .. plugin_name .. " — external tools")
  add("")

  if plan.manager then
    add(("Package manager: %s"):format(plan.manager.id))
  else
    add("Package manager: none detected — install commands unavailable.")
  end
  add(
    ("Tools declared: %d  ·  present: %d  ·  missing: %d"):format(
      #result.tools,
      #plan.present,
      #plan.missing
    )
  )
  add("")

  if #result.tools == 0 then
    add("This plugin declares no external tools.")
  end

  ---@param tool Lib.Deps.Tool
  ---@param found boolean
  local function add_tool(tool, found)
    local mark = found and "[ok]" or (tool.required and "[MISSING, required]" or "[missing]")
    add(("%s %s"):format(mark, tool.bin))
    add("    " .. tool.why)
    if #tool.why < WHY_TOO_SHORT then
      add("    ^ this 'why' is very short — say what the tool actually unlocks")
    end
    if tool.see then
      add("    see: " .. tool.see)
    end
    if not found then
      local pkg = plan.manager and tool.pkg[plan.manager.id] or nil
      if pkg then
        add("    " .. pm.render(pm.commands(plan.manager, { pkg })[1]))
      elseif plan.manager then
        add(("    no %s package declared for this tool"):format(plan.manager.id))
      end
    end
    add("")
  end

  -- Missing first: the reason anyone opens this view is to find out what
  -- isn't there, and required-but-missing is the most urgent line of all.
  for _, tool in ipairs(plan.missing) do
    if tool.required then
      add_tool(tool, false)
    end
  end
  for _, tool in ipairs(plan.missing) do
    if not tool.required then
      add_tool(tool, false)
    end
  end
  for _, tool in ipairs(plan.present) do
    add_tool(tool, true)
  end

  if #result.errors > 0 then
    add("## Spec problems")
    add("")
    for _, err in ipairs(result.errors) do
      if err.index == 0 then
        add(("- %s"):format(err.message))
      else
        add(("- entry #%d (%s): %s"):format(err.index, err.field or "?", err.message))
      end
    end
    add("")
  end

  if #plan.commands > 0 then
    add("## Install everything missing")
    add("")
    for _, argv in ipairs(plan.commands) do
      add("    " .. pm.render(argv))
    end
    add("")
    add(("Run  :Lib deps install %s  to open this in a terminal."):format(plugin_name))
  end

  return out
end

---Show `lines()`'s output for `plugin_name` in a named scratch split,
---reusing the same buffer on repeated calls.
---@param plugin_name string
---@param result Lib.Deps.ParseResult
---@return integer bufnr
---@return integer winid
function M.show(plugin_name, result)
  local open_named_scratch = require("lib.nvim.window.open_named_scratch")
  return open_named_scratch(
    "lib.nvim://deps/" .. plugin_name,
    M.lines(plugin_name, result),
    { filetype = "markdown", modifiable = false }
  )
end

---@type Lib.Deps.View
return M
