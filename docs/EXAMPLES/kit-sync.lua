-- docs/EXAMPLES/kit-sync.lua
--
-- Module:   lib.nvim.ui.kit.sync (lib.nvim.ui.kit.sync)
-- Scenario: bridge an async, callback-based kit component (input/form/
--           live_input) back to a plain synchronous return value via
--           vim.wait(), for call chains that were built around a blocking
--           vim.fn.input()/vim.fn.confirm() and can't easily be recast to
--           callback style (e.g. buffer_ctx.nvim's guard_interactive(), whose
--           return value flows synchronously through a generic template
--           dispatcher used by 15 other, unrelated templates).
--
-- Only safe to call from a normal call stack (a command handler, keymap
-- callback, ...) — never from a fast-event/libuv callback context, the same
-- restriction vim.wait() itself has.

local kit = require("lib.nvim.ui.kit")

-- kit.input, blocking: the function only returns once the user answers.
local name, cancelled = kit.sync(kit.input, {
  title = "Your name",
})
if not cancelled and name and name ~= "" then
  vim.notify("hello, " .. name)
end

-- kit.form, blocking: a synchronous multi-field prompt with no callback.
local values, form_cancelled = kit.sync(kit.form, {
  fields = {
    { name = "condition", label = "Condition to check (empty for 'condition')", default = "condition" },
    { name = "negation", label = "Use 'not' prefix? (y/n)", default = "n" },
  },
})
if not form_cancelled and values then
  local check = (values.negation:lower() == "y") and ("not " .. values.condition) or values.condition
  vim.notify(("if %s then ... end"):format(check))
end

-- A short custom timeout for a caller that would rather give up than block
-- indefinitely (the default is 10 minutes — a safety net, not the UX):
local _, _, timed_out = kit.sync(kit.input, { title = "Quick answer" }, 5000)
if timed_out then
  vim.notify("no answer in time", vim.log.levels.WARN)
end
