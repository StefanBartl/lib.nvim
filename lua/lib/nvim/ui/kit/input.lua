---@module 'lib.nvim.ui.kit.input'
--- Input component: a single-line themed prompt (a `vim.ui.input` replacement).
--- Opens focused in insert mode; `<CR>` submits the line, `<Esc>` cancels.

local surface = require("lib.nvim.ui.kit.surface")
local expand_path = require("lib.nvim.cross.fs.expand_path")

local api = vim.api

local M = {}

--- Open a single-line input.
---@param opts table  # { title|prompt, default, theme, width, relative, on_submit, on_cancel, expand_env }
--- `expand_env = true` runs the submitted line through `lib.nvim.cross.fs.expand_path`
--- (`~`, `$VAR`, `${VAR}`, `%VAR%`) before it reaches `on_submit` — opt-in, for
--- callers that know they're prompting for a path.
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}

  local title = opts.title or opts.prompt
  -- A float's title is drawn within its content width; a title longer than
  -- the default 40 cols gets silently truncated by Neovim (with a leading
  -- ellipsis) instead of wrapping, so widen the box to fit it.
  local title_width = title and vim.fn.strdisplaywidth(title) or 0

  local surf = surface.open({
    lines = { opts.default or "" },
    theme = opts.theme,
    title = title,
    width = opts.width or math.max(40, title_width),
    height = 1,
    relative = opts.relative or "cursor",
    enter = true,
    modifiable = true,
  })
  if not surf then
    return nil
  end

  local bufnr = surf.bufnr
  local done = false

  local function finish(submit)
    if done then
      return
    end
    done = true
    local line = api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
    -- Leave insert mode before closing to avoid a lingering mode state.
    pcall(vim.cmd, "stopinsert")
    surf:close()
    if submit then
      if opts.expand_env then
        line = expand_path(line)
      end
      if opts.on_submit then
        opts.on_submit(line)
      end
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    finish(true)
  end, { buffer = bufnr, nowait = true })
  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    finish(false)
  end, { buffer = bufnr, nowait = true })
  surf:on_close(function()
    finish(false)
  end)

  -- Place the cursor at end of the default text and enter insert mode.
  if surf:is_valid() then
    api.nvim_win_set_cursor(surf.winid, { 1, #(opts.default or "") })
    vim.cmd("startinsert!")
  end

  return surf
end

return M
