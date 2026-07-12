---@module 'lib.nvim.ui.kit.picker'
--- Interactive picker built on the layout `picker` template: an insert-mode
--- prompt that debounces keystrokes into `on_change(query)` (the caller fills
--- the results slot), moves the selection in the results slot with
--- <C-n>/<C-p>/arrows, submits the highlighted result with <CR>, and closes on
--- <Esc>. This is the "works like Telescope out of the box" behavior from
--- docs/ROADMAP/UI-KIT-CONCEPT.md §7a.
---
--- `opts.prompt = "plain"` falls back to a bare `kit.layout.template("picker")`
--- whose prompt slot the caller wires itself.

local layout = require("lib.nvim.ui.kit.layout")
local map = require("lib.nvim.map")

local api = vim.api

local M = {}

--- Move the cursor in `win` by `delta` rows, wrapping around.
local function move_in(win, buf, delta)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local count = math.max(1, api.nvim_buf_line_count(buf))
  local line = api.nvim_win_get_cursor(win)[1] + delta
  if line < 1 then
    line = count
  elseif line > count then
    line = 1
  end
  pcall(api.nvim_win_set_cursor, win, { line, 0 })
end

--- Open an interactive picker.
---@param opts table  # { theme?, debounce?, on_change(query), on_submit(idx, text), prompt? }
---@return table|nil  # handle: { slots, query(), set_results(lines), move(delta), submit(), close() }
function M.open(opts)
  opts = opts or {}

  if opts.prompt == "plain" then
    return layout.template("picker", opts)
  end

  ---@type fun(query: string)
  local on_change = opts.on_change or function(_) end
  ---@type fun(idx: integer, text: string)
  local on_submit = opts.on_submit or function(_, _) end
  local debounce_ms = tonumber(opts.debounce) or 80

  local group = layout.mount(layout.templates.picker.spec, {
    theme = opts.theme,
    enter = "prompt",
    slot = {
      prompt = { modifiable = true, filetype = "lib-kit-picker-prompt" },
      results = { wo = { cursorline = true }, filetype = "lib-kit-picker-results" },
    },
  })

  local prompt = group.slots.prompt
  local results = group.slots.results
  if not (prompt and results) then
    group.close()
    return nil
  end

  -- Selection highlight on the results slot.
  local cur = api.nvim_get_option_value("winhighlight", { win = results.winid })
  local sep = cur ~= "" and "," or ""
  pcall(
    api.nvim_set_option_value,
    "winhighlight",
    cur .. sep .. "CursorLine:KitSelection",
    { win = results.winid }
  )

  local function finish_close()
    pcall(vim.cmd, "stopinsert")
    group.close()
  end

  local handle = { slots = group.slots }

  ---@return string
  function handle.query()
    if not api.nvim_buf_is_valid(prompt.bufnr) then
      return ""
    end
    return api.nvim_buf_get_lines(prompt.bufnr, 0, 1, false)[1] or ""
  end

  ---@param lines string[]
  function handle.set_results(lines)
    results:set_lines(lines or {})
    if results:is_valid() then
      pcall(api.nvim_win_set_cursor, results.winid, { 1, 0 })
    end
  end

  ---@param delta integer
  function handle.move(delta)
    move_in(results.winid, results.bufnr, delta)
  end

  --- Submit the highlighted result: on_submit(index, line_text), then close.
  function handle.submit()
    if not results:is_valid() then
      return
    end
    local idx = api.nvim_win_get_cursor(results.winid)[1]
    local text = api.nvim_buf_get_lines(results.bufnr, idx - 1, idx, false)[1]
    finish_close()
    on_submit(idx, text)
  end

  function handle.close()
    finish_close()
  end

  -- Debounced query notifications.
  local timer
  local function schedule_change()
    if timer then
      timer:stop()
      pcall(timer.close, timer)
      timer = nil
    end
    timer = vim.uv.new_timer()
    timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        if timer then
          timer:stop()
          pcall(timer.close, timer)
          timer = nil
        end
        on_change(handle.query())
      end)
    )
  end

  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt.bufnr,
    callback = schedule_change,
    desc = "lib.nvim.ui.kit.picker: query changed",
  })

  local mo = { buffer = prompt.bufnr, nowait = true }
  map({ "i", "n" }, "<CR>", handle.submit, mo)
  map({ "i", "n" }, "<C-n>", function()
    handle.move(1)
  end, mo)
  map({ "i", "n" }, "<C-p>", function()
    handle.move(-1)
  end, mo)
  map({ "i", "n" }, "<Down>", function()
    handle.move(1)
  end, mo)
  map({ "i", "n" }, "<Up>", function()
    handle.move(-1)
  end, mo)
  map({ "i", "n" }, "<Esc>", finish_close, mo)

  prompt:focus()
  vim.cmd("startinsert")

  return handle
end

return M
