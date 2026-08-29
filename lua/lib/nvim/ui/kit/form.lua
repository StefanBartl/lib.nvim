---@module 'lib.nvim.ui.kit.form'
--- Form component: a sequential multi-field prompt — one `kit.input` per
--- field, chained field-by-field into a single keyed result table. This is
--- the "several `vim.fn.input`/`vim.ui.input` calls in a row, each optional
--- with its own default" pattern that got hand-rolled independently (e.g.
--- sandbox.nvim's `container_commands.lua` chaining Image/Name/Ports/Volumes/
--- Env prompts by hand, buffer_ctx.nvim's own `boilerplate/templates/utils.lua`
--- `process_prompts` helper).
---
--- Field contract: `{ name, label|prompt, default?, required?, expand_env?,
--- theme?, width?, relative? }`. `name` is the key the field's answer is
--- stored under in the result table handed to `on_submit`.
---
--- `<Esc>` on a field:
---   - `required = true`  -> aborts the whole form; `on_cancel` fires, no
---     further fields are shown (matches sandbox.nvim's Image field: the one
---     mandatory field in that chain, where Esc really means "abort").
---   - otherwise (default) -> skips the field (its value becomes `default`
---     or `""`) and the form continues to the next field (matches
---     sandbox.nvim's Name/Ports/Volumes/Env fields: Esc = "leave this one
---     blank", not "cancel everything").

local input = require("lib.nvim.ui.kit.input")

local M = {}

--- Open a sequential multi-field form.
---@param opts table  # { fields = { { name, label|prompt, default?, required?, expand_env?, theme?, width?, relative? }, ... }, theme?, width?, relative?, on_submit(values: table), on_cancel? }
---@return Lib.UI.Kit.Surface|nil  # the first field's input surface (nil if `fields` is empty)
function M.open(opts)
  opts = opts or {}
  local fields = opts.fields or {}
  local values = {}

  local function step(i)
    local field = fields[i]
    if not field then
      if opts.on_submit then
        opts.on_submit(values)
      end
      return nil
    end

    return input.open({
      title = field.label or field.prompt,
      prompt = field.label or field.prompt,
      default = field.default,
      theme = field.theme or opts.theme,
      width = field.width or opts.width,
      relative = field.relative or opts.relative,
      expand_env = field.expand_env,
      on_submit = function(line)
        values[field.name] = line
        step(i + 1)
      end,
      on_cancel = function()
        if field.required then
          if opts.on_cancel then
            opts.on_cancel()
          end
          return
        end
        values[field.name] = field.default or ""
        step(i + 1)
      end,
    })
  end

  return step(1)
end

return M
