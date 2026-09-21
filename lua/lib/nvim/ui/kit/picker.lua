---@module 'lib.nvim.ui.kit.picker'
--- Interactive picker built on the layout `picker` template: an insert-mode
--- prompt that debounces keystrokes into `on_change(query)` (the caller fills
--- the results slot), moves the selection in the results slot with
--- <C-n>/<C-p>/arrows, submits the highlighted result with <CR>, and closes on
--- <Esc>. This is the "works like Telescope out of the box" behavior from
--- the layout engine.
---
--- `opts.prompt = "plain"` falls back to a bare `kit.layout.template("picker")`
--- whose prompt slot the caller wires itself.

local layout = require("lib.nvim.ui.kit.layout")
local map = require("lib.nvim.bindings.keymap")

local api = vim.api
local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

---@internal
--- Move the cursor in `win` by `delta` rows, wrapping around.
---@param win integer
---@param buf integer
---@param delta integer
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

  -- Declared here, stopped in `finish_close` and in `prompt`'s `on_close`
  -- below: closing the picker before the debounce fires -- whether via our
  -- own keymaps or an external `:q`/`:close`/`<C-w>c` -- must not leave a
  -- stray timer that calls `on_change` on a picker that no longer exists.
  local timer

  local function stop_timer()
    if timer then
      timer:stop()
      pcall(timer.close, timer)
      timer = nil
    end
  end

  ---@internal
  ---Recompute the template's geometry for the current editor size and
  ---reapply it to every mounted slot -- `layout.compute` is pure, so calling
  ---it again with the same spec is the whole fix. Keyed off `geo.slots`
  ---itself, not a hardcoded slot-name list: the picker template also mounts
  ---a "preview" slot (`layout.templates.picker.spec`) that `M.open` never
  ---names locally, and a fixed `{"prompt", "results"}` loop silently left it
  ---stuck at its open-time position and size on every resize.
  local function relayout()
    local geo = layout.compute(layout.templates.picker.spec)
    for name, g in pairs(geo.slots) do
      local surf = group.slots[name]
      if surf and surf:is_valid() then
        pcall(api.nvim_win_set_config, surf.winid, g)
      end
    end
  end

  local resize_group = autocmd.group("lib_kit_picker_resize_" .. prompt.winid, true)
  autocmd.create("VimResized", relayout, {
    group = resize_group,
    record = false, -- throwaway per-window hook: not recorded (see lib.nvim.ui.kit.surface)
    desc = "lib.nvim.ui.kit.picker: keep the picker sized to the editor",
  })
  -- Hung off the surface's own close lifecycle, not just `finish_close`:
  -- `layout.mount`'s `close_all` (wired to every slot's `on_close`) tears the
  -- picker down when a slot window is closed externally too (a plain `:q`,
  -- `:close`, `<C-w>c` -- none of which run our own keymaps), and that path
  -- never called `finish_close`, leaking this augroup and its autocmd for
  -- the rest of the session -- and, for the same reason, leaving the
  -- debounce timer running to later call `on_change` on buffers that may
  -- already be gone. `prompt:close()` always runs as part of `close_all`, on
  -- every path, so anchoring cleanup to `prompt`'s own `on_close` covers all
  -- of them, `finish_close` included.
  prompt:on_close(function()
    pcall(api.nvim_del_augroup_by_id, resize_group)
    stop_timer()
  end)

  local function finish_close()
    stop_timer()
    pcall(function()
      vim.cmd("stopinsert")
    end)
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
  local function schedule_change()
    stop_timer()
    timer = vim.uv.new_timer()
    -- libuv returns nil rather than raising when it cannot allocate a
    -- handle; without a timer the query simply is not re-run.
    if not timer then
      return
    end
    timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        stop_timer()
        on_change(handle.query())
      end)
    )
  end

  -- Per-instance group (matches `resize_group` above): a fixed name here
  -- would let a second concurrent `M.open()` call -- `kit.picker` mounts no
  -- singleton and nothing stops a caller from opening one from inside
  -- another's `on_change`/`on_submit` -- clear the first picker's own
  -- TextChanged autocmd out from under it on `autocmd.group(name, true)`'s
  -- clear-on-create, silently killing its debounce while it is still open.
  autocmd.create({ "TextChangedI", "TextChanged" }, schedule_change, {
    group = autocmd.group("lib_kit_picker_" .. prompt.winid, true),
    buffer = prompt.bufnr,
    record = false, -- throwaway per-window hook: not recorded (see lib.nvim.ui.kit.surface)
    desc = "lib.nvim.ui.kit.picker: query changed",
  })

  -- Throwaway buffer-local keys: not recorded (see lib.nvim.ui.kit.chooser's `mo`).
  local mo = { buffer = prompt.bufnr, nowait = true, record = false }
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
