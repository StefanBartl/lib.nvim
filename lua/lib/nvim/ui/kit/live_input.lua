---@module 'lib.nvim.ui.kit.live_input'
--- Live-incremental input: a single-line insert-mode prompt (like `kit.input`)
--- that additionally debounces keystrokes into `on_change(query)` as the user
--- types — for filter/search boxes that need to refresh a results list or
--- preview on every keystroke, not just on submit. This is the floating
--- prompt-buffer + `TextChangedI`-debounce pattern that got hand-rolled
--- independently in filetree.nvim's `features/search/live_search/init.lua`
--- and `features/search/filter/init.lua` (see docs/ROADMAP/personal/
--- lib_nvim/ui_kit_migration.md §5.3). The debounce timer itself is the same
--- one `kit.picker`'s prompt slot uses internally.

local surface = require("lib.nvim.ui.kit.surface")

local api = vim.api
local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

--- Open a live-incremental input.
---@param opts table  # { title|prompt, default?, theme?, width?, relative?, row?, col?, debounce?, on_change(query: string), on_submit?(query: string), on_cancel?() }
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
    row = opts.row,
    col = opts.col,
    enter = true,
    modifiable = true,
    filetype = opts.filetype or "lib-kit-live-input",
  })
  if not surf then
    return nil
  end

  local bufnr = surf.bufnr
  local on_change = opts.on_change or function(_) end
  local debounce_ms = tonumber(opts.debounce) or 80
  local done = false
  local timer

  local function query()
    if not api.nvim_buf_is_valid(bufnr) then
      return ""
    end
    return api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  end

  local function stop_timer()
    if timer then
      timer:stop()
      pcall(timer.close, timer)
      timer = nil
    end
  end

  local function schedule_change()
    stop_timer()
    timer = vim.uv.new_timer()
    timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        stop_timer()
        if not done then
          on_change(query())
        end
      end)
    )
  end

  local function finish(submit)
    if done then
      return
    end
    done = true
    stop_timer()
    local line = query()
    -- Leave insert mode before closing to avoid a lingering mode state.
    pcall(vim.cmd, "stopinsert")
    surf:close()
    if submit then
      if opts.on_submit then
        opts.on_submit(line)
      end
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end

  autocmd.create({ "TextChangedI", "TextChanged" }, schedule_change, {
    group = autocmd.group("lib_kit_live_input", true),
    buffer = bufnr,
    desc = "lib.nvim.ui.kit.live_input: query changed",
  })

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    finish(true)
  end, { buffer = bufnr, nowait = true })
  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    finish(false)
  end, { buffer = bufnr, nowait = true })
  surf:on_close(function()
    stop_timer()
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
