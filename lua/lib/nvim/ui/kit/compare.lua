---@module 'lib.nvim.ui.kit.compare'
--- Pick two items out of one picker and view them side by side. Motivated by
--- images.nvim's "browse images, pick two, view them next to each other"
--- roadmap item — but nothing here is image-specific, hence a `kit`
--- component instead of images.nvim-local code: any consumer that can render
--- an item into a `surface` (buffer text, a diff, a terminal-drawn image, …)
--- can reuse this.
---
--- Engine-independent by construction: built on the same primitives as
--- `kit.picker` (`surface` + hand-rolled geometry), not a wrapper around
--- telescope/fzf-lua/snacks. `layout.compute`'s grid model (rows containing
--- cols) is deliberately NOT reused here — the "marked" state below needs a
--- column that is itself split into two rows while the preview column next
--- to it spans the full height, which that grid cannot express. Rather than
--- bend the shared layout engine for one caller, this module computes its
--- three states' geometry directly, the same way `layout.lua` computes its
--- own slots internally.
---
--- Three states, entered in order (a fresh `open()` starts in SEARCH):
---
---   SEARCH   prompt (top) + results (bottom-left) + live preview (right).
---            Typing filters; <C-n>/<C-p>/arrows move the selection;
---            `render(current_item, preview_surface)` runs on every move.
---   MARKED   (`mark_key`, default <M-c>, or <CR>): the current item freezes
---            into the "marked" slot (bottom-left, below results, which
---            shrinks to make room); the live preview keeps following the
---            selection on the right while the user keeps searching.
---   COMPARE  (<CR> again): prompt/results/marked are gone, replaced by two
---            full-height preview panes side by side — the marked item and
---            the just-confirmed second item. `q`/`<Esc>` on either pane
---            closes the whole thing and fires `on_close(a, b)`.
---
--- `<CR>` doing double duty (marks the first pick in SEARCH, confirms the
--- second in MARKED) is a deliberate simplification over adding a second
--- dedicated keymap: it reads naturally as "confirm whichever pick this is".
---
--- `render(item, surface)` is the only rendering contract: for text, the
--- caller just does `surface:set_lines(...)`; for something that isn't
--- buffer content at all (images.nvim draws via terminal escape sequences at
--- a window's screen coordinates, not into its buffer), the caller draws
--- directly using `surface.winid`'s geometry. Because such overlays don't
--- belong to any buffer, they survive a `surface:close()` — `opts.clear`, if
--- given, runs once before every state transition so a caller with that kind
--- of overlay can wipe it before the old windows disappear and new ones
--- (with different coordinates) take their place.
---
--- No text-diff computation in this first version — the second pane shows
--- the plain rendered content, matching the "two preview texts side by
--- side" the feature was asked for. `lib.lua.diff` (`myers`/`lines`,
--- already in this repo) is a natural place to add diff highlighting later,
--- for a caller that wants it — out of scope for now.

local surface = require("lib.nvim.ui.kit.surface")
local map = require("lib.nvim.map")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.compare]")

local api = vim.api

local M = {}

--- Border thickness assumed per slot (one cell all around) — mirrors
--- `layout.lua`'s own constant, needed here because that module's
--- `to_content` helper is private.
local BORDER = 1

---@internal
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@return table
local function to_content(x, y, w, h)
  return {
    relative = "editor",
    row = y + BORDER,
    col = x + BORDER,
    width = math.max(1, w - 2 * BORDER),
    height = math.max(1, h - 2 * BORDER),
  }
end

---@internal
---Outer box centered on the editor: 85% of both dimensions.
---@return integer row0, integer col0, integer width, integer height
local function outer_geo()
  local cols = vim.o.columns
  local lines = vim.o.lines - (vim.o.cmdheight or 1)
  local ow = math.floor(cols * 0.85)
  local oh = math.floor(lines * 0.85)
  local row0 = math.max(0, math.floor((lines - oh) / 2))
  local col0 = math.max(0, math.floor((cols - ow) / 2))
  return row0, col0, ow, oh
end

-- Outer row height 3 = 1 content line + 2 border rows, same numbers
-- `layout.templates.picker` uses for its own prompt row.
local PROMPT_H = 3

---@internal
---SEARCH state geometry: prompt on top, results | preview below.
local function geo_search()
  local row0, col0, ow, oh = outer_geo()
  local rest_h = oh - PROMPT_H
  local results_w = math.floor(ow * 0.4)
  local preview_w = ow - results_w
  return {
    prompt = to_content(col0, row0, ow, PROMPT_H),
    results = to_content(col0, row0 + PROMPT_H, results_w, rest_h),
    preview = to_content(col0 + results_w, row0 + PROMPT_H, preview_w, rest_h),
  }
end

---@internal
---MARKED state geometry: prompt on top; left column split into results
---(top) + marked preview (bottom); live preview spans the full height on
---the right — the shape `layout.compute`'s grid cannot express (see the
---module doc).
local function geo_marked()
  local row0, col0, ow, oh = outer_geo()
  local rest_h = oh - PROMPT_H
  local results_w = math.floor(ow * 0.4)
  local preview_w = ow - results_w
  local results_h = math.floor(rest_h * 0.5)
  local marked_h = rest_h - results_h
  return {
    prompt = to_content(col0, row0, ow, PROMPT_H),
    results = to_content(col0, row0 + PROMPT_H, results_w, results_h),
    marked = to_content(col0, row0 + PROMPT_H + results_h, results_w, marked_h),
    preview = to_content(col0 + results_w, row0 + PROMPT_H, preview_w, rest_h),
  }
end

---@internal
---COMPARE state geometry: two full-height panes side by side.
local function geo_compare()
  local row0, col0, ow, oh = outer_geo()
  local a_w = math.floor(ow / 2)
  local b_w = ow - a_w
  return {
    a = to_content(col0, row0, a_w, oh),
    b = to_content(col0 + a_w, row0, b_w, oh),
  }
end

--- Open the compare picker.
---@param opts Lib.UI.Kit.CompareOpts
---@return Lib.UI.Kit.CompareHandle|nil
function M.open(opts)
  opts = opts or {}
  local items = opts.items or {}
  local on_close = opts.on_close

  if #items == 0 then
    if on_close then
      pcall(on_close, nil, nil)
    end
    return nil
  end

  local format_item = opts.format_item or tostring
  local render = opts.render
  if type(render) ~= "function" then
    notify.error("opts.render(item, surface) is required")
    return nil
  end
  local clear = opts.clear
  local mark_key = opts.mark_key or "<M-c>"
  local title = opts.title or "Compare"
  local theme = opts.theme

  ---@internal
  ---Substring match on `format_item`, case-insensitive — used unless the
  ---caller supplies its own `opts.query`.
  ---@param q string
  ---@return any[]
  local function default_filter(q)
    if q == "" then
      return items
    end
    local ql = q:lower()
    local out = {}
    for _, it in ipairs(items) do
      if tostring(format_item(it)):lower():find(ql, 1, true) then
        out[#out + 1] = it
      end
    end
    return out
  end

  ---@type table<string, Lib.UI.Kit.Surface>
  local surfaces = {}
  local filtered = items
  local sel_idx = 1
  local marked_item = nil
  local confirmed_b = nil
  local query_text = ""
  local finished = false
  local transitioning = false
  ---@type "search"|"marked"|"compare"
  local current_state = "search"

  ---@internal
  local function fire_close(a, b)
    if finished then
      return
    end
    finished = true
    if on_close then
      pcall(on_close, a, b)
    end
  end

  ---@internal
  ---Tear down every currently mounted surface. Guarded by `transitioning` so
  ---a surface's own `on_close` (fired by our own `:close()` call below,
  ---synchronously) does not misread this as a user-initiated dismissal.
  local function unmount()
    transitioning = true
    if clear then
      pcall(clear)
    end
    for _, s in pairs(surfaces) do
      if s then
        s:close()
      end
    end
    surfaces = {}
    transitioning = false
  end

  ---@internal
  local function teardown_and_close(a, b)
    unmount()
    fire_close(a, b)
  end

  ---@internal
  ---Register `on_user_close` on every surface in the current mount, firing
  ---only when a window closes for a reason other than our own transition.
  ---@param on_user_close fun()
  local function wire_group_close(on_user_close)
    for _, s in pairs(surfaces) do
      if s then
        s:on_close(function()
          if not transitioning then
            on_user_close()
          end
        end)
      end
    end
  end

  local enter_search, enter_marked, enter_compare

  ---@internal
  local function render_results()
    local rs = surfaces.results
    if not rs then
      return
    end
    local lines = {}
    for i, it in ipairs(filtered) do
      lines[i] = tostring(format_item(it))
    end
    rs:set_lines(lines)
    if rs:is_valid() and #filtered > 0 then
      pcall(api.nvim_win_set_cursor, rs.winid, { sel_idx, 0 })
    end
  end

  ---@internal
  local function render_preview()
    local ps = surfaces.preview
    local item = filtered[sel_idx]
    if ps and item then
      pcall(render, item, ps)
    end
  end

  ---@internal
  ---@param delta integer
  local function move(delta)
    if #filtered == 0 then
      return
    end
    sel_idx = ((sel_idx - 1 + delta) % #filtered) + 1
    render_results()
    render_preview()
  end

  ---@internal
  ---@param q string
  local function on_query_change(q)
    query_text = q
    filtered = opts.query and opts.query(q, items) or default_filter(q)
    sel_idx = 1
    render_results()
    render_preview()
  end

  local debounce_timer
  ---@internal
  ---@param prompt_buf integer
  local function schedule_change(prompt_buf)
    if debounce_timer then
      debounce_timer:stop()
      pcall(debounce_timer.close, debounce_timer)
      debounce_timer = nil
    end
    debounce_timer = vim.uv.new_timer()
    debounce_timer:start(
      80,
      0,
      vim.schedule_wrap(function()
        if debounce_timer then
          debounce_timer:stop()
          pcall(debounce_timer.close, debounce_timer)
          debounce_timer = nil
        end
        if not api.nvim_buf_is_valid(prompt_buf) then
          return
        end
        on_query_change(api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or "")
      end)
    )
  end

  ---@internal
  ---Apply the selection highlight to the results window, and wire the
  ---prompt buffer's shared keymaps/autocmds/focus. Shared by SEARCH/MARKED,
  ---which differ only in geometry and what <CR> does.
  ---@param on_confirm fun()
  ---@param on_abort fun()
  ---@param extra_keys table<string, fun()>|nil additional lhs -> action bound the same way (i+n, this buffer)
  local function wire_prompt(on_confirm, on_abort, extra_keys)
    local rs = surfaces.results
    local cur = api.nvim_get_option_value("winhighlight", { win = rs.winid })
    local sep = cur ~= "" and "," or ""
    pcall(api.nvim_set_option_value, "winhighlight", cur .. sep .. "CursorLine:KitSelection", { win = rs.winid })

    local pbuf = surfaces.prompt.bufnr
    if query_text ~= "" then
      api.nvim_buf_set_lines(pbuf, 0, 1, false, { query_text })
    end

    api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      buffer = pbuf,
      callback = function()
        schedule_change(pbuf)
      end,
      desc = "lib.nvim.ui.kit.compare: query changed",
    })

    local mo = { buffer = pbuf, nowait = true }
    map({ "i", "n" }, "<CR>", on_confirm, mo)
    map({ "i", "n" }, "<C-n>", function()
      move(1)
    end, mo)
    map({ "i", "n" }, "<C-p>", function()
      move(-1)
    end, mo)
    map({ "i", "n" }, "<Down>", function()
      move(1)
    end, mo)
    map({ "i", "n" }, "<Up>", function()
      move(-1)
    end, mo)
    map({ "i", "n" }, "<Esc>", on_abort, mo)
    for lhs, fn in pairs(extra_keys or {}) do
      map({ "i", "n" }, lhs, fn, mo)
    end

    render_results()
    render_preview()
    surfaces.prompt:focus()
    vim.cmd("startinsert")
  end

  ---@internal
  local function mark_current()
    if current_state ~= "search" or #filtered == 0 then
      return
    end
    marked_item = filtered[sel_idx]
    enter_marked()
  end

  ---@internal
  local function confirm_second()
    if current_state ~= "marked" or #filtered == 0 then
      return
    end
    enter_compare(filtered[sel_idx])
  end

  enter_search = function()
    current_state = "search"
    unmount()
    local geo = geo_search()
    surfaces.prompt = surface.open(vim.tbl_extend("force", geo.prompt, {
      theme = theme,
      enter = true,
      modifiable = true,
      filetype = "lib-kit-compare-prompt",
      title = title,
    }))
    surfaces.results = surface.open(vim.tbl_extend("force", geo.results, {
      theme = theme,
      filetype = "lib-kit-compare-results",
      wo = { cursorline = true },
    }))
    surfaces.preview = surface.open(vim.tbl_extend("force", geo.preview, {
      theme = theme,
      filetype = "lib-kit-compare-preview",
      title = "preview",
    }))
    if not (surfaces.prompt and surfaces.results and surfaces.preview) then
      notify.error("failed to open the compare picker")
      teardown_and_close(nil, nil)
      return
    end

    wire_group_close(function()
      teardown_and_close(nil, nil)
    end)
    wire_prompt(mark_current, function()
      teardown_and_close(nil, nil)
    end, { [mark_key] = mark_current })
  end

  enter_marked = function()
    current_state = "marked"
    local frozen = marked_item
    unmount()
    local geo = geo_marked()
    surfaces.prompt = surface.open(vim.tbl_extend("force", geo.prompt, {
      theme = theme,
      enter = true,
      modifiable = true,
      filetype = "lib-kit-compare-prompt",
      title = title,
    }))
    surfaces.results = surface.open(vim.tbl_extend("force", geo.results, {
      theme = theme,
      filetype = "lib-kit-compare-results",
      wo = { cursorline = true },
    }))
    surfaces.marked = surface.open(vim.tbl_extend("force", geo.marked, {
      theme = theme,
      filetype = "lib-kit-compare-marked",
      title = "marked",
    }))
    surfaces.preview = surface.open(vim.tbl_extend("force", geo.preview, {
      theme = theme,
      filetype = "lib-kit-compare-preview",
      title = "preview",
    }))
    if not (surfaces.prompt and surfaces.results and surfaces.marked and surfaces.preview) then
      notify.error("failed to open the compare picker")
      teardown_and_close(frozen, nil)
      return
    end

    wire_group_close(function()
      teardown_and_close(frozen, nil)
    end)
    pcall(render, frozen, surfaces.marked)

    wire_prompt(confirm_second, function()
      teardown_and_close(frozen, nil)
    end)
  end

  enter_compare = function(chosen_b)
    current_state = "compare"
    local a, b = marked_item, chosen_b
    -- Tracked separately from the local `b` so a programmatic `handle.close()`
    -- (unlike the q/<Esc> keymaps below, which already close over `a, b`)
    -- still reports the confirmed second pick instead of losing it to nil.
    confirmed_b = b
    unmount()
    local geo = geo_compare()
    surfaces.a = surface.open(vim.tbl_extend("force", geo.a, {
      theme = theme,
      enter = true,
      filetype = "lib-kit-compare-a",
      title = "A",
    }))
    surfaces.b = surface.open(vim.tbl_extend("force", geo.b, {
      theme = theme,
      filetype = "lib-kit-compare-b",
      title = "B",
    }))
    if not (surfaces.a and surfaces.b) then
      notify.error("failed to open the compare view")
      teardown_and_close(a, b)
      return
    end

    local function close_compare()
      teardown_and_close(a, b)
    end
    wire_group_close(close_compare)
    for _, name in ipairs({ "a", "b" }) do
      local mo = { buffer = surfaces[name].bufnr, nowait = true }
      map("n", "q", close_compare, mo)
      map("n", "<Esc>", close_compare, mo)
    end

    pcall(render, a, surfaces.a)
    pcall(render, b, surfaces.b)
    surfaces.a:focus()
  end

  enter_search()

  -- `state`/`slots`/`move`/`mark`/`confirm` mirror `kit.picker`'s handle
  -- (`slots`, `move`, `submit`) so the state machine is directly testable
  -- headlessly, the same way — no keypress simulation needed.
  return {
    close = function()
      teardown_and_close(marked_item, confirmed_b)
    end,
    ---@return "search"|"marked"|"compare"
    state = function()
      return current_state
    end,
    ---@return table<string, Lib.UI.Kit.Surface>
    slots = function()
      return surfaces
    end,
    move = move,
    mark = mark_current,
    confirm = function()
      if current_state == "search" then
        mark_current()
      elseif current_state == "marked" then
        confirm_second()
      end
    end,
  }
end

return M
