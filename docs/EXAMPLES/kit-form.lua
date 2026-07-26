-- docs/EXAMPLES/kit-form.lua
--
-- Module:   lib.nvim.ui.kit.form (lib.nvim.ui.kit.form)
-- Scenario: a sequential multi-field prompt — one `kit.input` per field,
--           chained into a single keyed result table. This is the "several
--           vim.fn.input/vim.ui.input calls in a row, each optional with its
--           own default" pattern that kept getting hand-rolled independently
--           (sandbox.nvim's container_commands.lua chaining Image/Name/
--           Ports/Volumes/Env by hand, buffer_ctx.nvim's own
--           `process_prompts` helper).

local kit = require("lib.nvim.ui.kit")

-- A container run form: Image is the only mandatory field (required = true,
-- so <Esc> there aborts the whole form); everything else is optional and
-- <Esc> just leaves it blank and moves on.
kit.form({
  title = "docker run",
  fields = {
    { name = "image", label = "Image", required = true },
    { name = "name", label = "Name" },
    { name = "ports", label = "Ports" },
    { name = "volumes", label = "Volumes" },
    { name = "env", label = "Env" },
  },
  on_submit = function(values)
    -- values = { image = "...", name = "...", ports = "...", ... }
    vim.notify(("docker run %s"):format(values.image))
  end,
  on_cancel = function()
    vim.notify("run cancelled", vim.log.levels.WARN)
  end,
})

-- A shorter form with defaults per field (e.g. column-align's target column
-- + fill character) -- <Esc> on either keeps its default and moves on, since
-- neither is marked required.
kit.form({
  fields = {
    { name = "column", label = "Target column", default = "80" },
    { name = "fill", label = "Fill char", default = " " },
  },
  on_submit = function(values)
    vim.notify(("align to col %s with %q"):format(values.column, values.fill))
  end,
})

-- routed via kit.popup({ type = "form" }) too:
kit.popup({
  type = "form",
  fields = { { name = "path", label = "Path", expand_env = true } },
  on_submit = function(values)
    vim.notify("resolved: " .. values.path)
  end,
})
