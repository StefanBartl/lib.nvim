---@module 'lib.nvim.ui.kit.select'
--- Select component. Backed by the native themed chooser
--- (lib.nvim.ui.kit.chooser), which absorbed and replaced the former
--- lib.nvim.ui.hover_select module (now removed; see UI-KIT-CONCEPT.md §10).
---
--- `respect_override`: when true, defers to `vim.ui.select` instead of kit's
--- own chooser IF something has replaced Neovim's builtin `vim.ui.select`
--- (telescope-ui-select.nvim, fzf-lua, dressing.nvim, ...). Detection is
--- source-based (native `vim.ui.select` is defined in the runtime's own
--- `vim/ui.lua`; any override replaces the function wholesale, so its
--- `debug.getinfo(...).source` points elsewhere) rather than load-order-
--- dependent, so it works regardless of when kit itself loads relative to
--- the overriding plugin's setup(). Several call sites across the author's
--- plugins (open.nvim's handler picker, gopath.nvim's alternate-file
--- fallback, emojis.nvim's no-backend fallback, diff.nvim's run_buffers,
--- cascade.nvim's word_cycle) used to call `vim.ui.select` directly instead
--- of kit.select specifically to respect the user's configured picker
--- backend -- `respect_override = true` gets that same behavior plus kit's
--- nicer default chooser for free when nothing else is installed. See
--- docs/ROADMAP/personal/lib_nvim/ui_kit_migration.md §2 for the audit.
---
--- Callback contract (identical on both paths, so a call site behaves the
--- same whether or not the user has an override installed):
---   - `on_select(item, idx)` fires only for a real selection, and always
---     with the ORIGINAL item (not its `format_item` display string).
---   - `on_cancel()` fires when the user dismisses the picker, when there is
---     nothing to pick from, and when the picker could not be opened at all.
---     Callers that must always hear back exactly once (a waiting coroutine,
---     a documented "calls back when finished" contract) should pass it.
---     Note this differs from `vim.ui.select`, which signals cancellation by
---     calling its single callback with `nil`.

local chooser = require("lib.nvim.ui.kit.chooser")

local M = {}

--- Set while delegating to `vim.ui.select`. A user may legitimately route
--- `vim.ui.select` INTO kit (making kit the global picker backend); without
--- this guard a `respect_override` call would delegate to `vim.ui.select`,
--- which calls back into kit.select, which delegates again -- unbounded
--- recursion ending in a stack overflow.
local delegating = false

---@internal
---The current `vim.ui.select`, or nil if it is somehow not callable.
---@return function|nil
local function ui_select_fn()
  local sel = vim.ui and vim.ui.select
  return type(sel) == "function" and sel or nil
end

---@internal
---Whether `sel` is something other than Neovim's builtin `vim.ui.select`.
---Deliberately re-checked on every call rather than cached: plugins install
---their override from `setup()`, which can run long after kit is required
---(and can be swapped again at runtime), so a cached answer would go stale.
---@param sel function
---@return boolean overridden
local function is_overridden(sel)
  local ok, info = pcall(debug.getinfo, sel, "S")
  if not ok or type(info) ~= "table" or type(info.source) ~= "string" then
    return false
  end
  return not (info.source:gsub("\\", "/")):match("/vim/ui%.lua$")
end

---@internal
---Render one item to a single buffer-safe display line. Mirrors
---`vim.ui.select`'s contract (`format_item` defaults to `tostring`), and
---additionally flattens embedded newlines -- the chooser writes these
---straight into a buffer, where a multi-line string is a hard error.
---@param item any
---@param format_item? fun(item: any): any
---@return string
local function display_line(item, format_item)
  local rendered = format_item and format_item(item) or item
  if type(rendered) ~= "string" then
    rendered = tostring(rendered)
  end
  return (rendered:gsub("[\r\n]+", " "))
end

--- Open a list chooser.
---@param opts table  # { selection|items, on_select, on_cancel?, message|title, format_item?, multi, relative, theme, width, height, respect_override?, initial_index? }
---@return Lib.UI.Kit.Surface|nil  # nil when delegating, cancelled up-front, or the float could not open
function M.open(opts)
  opts = opts or {}
  local items = opts.selection or opts.items or {}
  local on_select = type(opts.on_select) == "function" and opts.on_select or nil
  local on_cancel = type(opts.on_cancel) == "function" and opts.on_cancel or nil
  local multi = opts.multi or opts.multi_select or false
  local title = opts.title or opts.message

  local function cancel()
    if on_cancel then
      on_cancel()
    end
  end

  -- An empty list is a legitimate "nothing to pick" state, not a caller bug:
  -- report it as a cancellation instead of opening an empty float (or
  -- letting the chooser emit an error notification).
  if type(items) ~= "table" or #items == 0 then
    cancel()
    return nil
  end

  local sel = ui_select_fn()
  if opts.respect_override and not delegating and sel and is_overridden(sel) then
    delegating = true
    -- pcall so the guard is always cleared, even if the override throws.
    local ok, err = pcall(sel, items, {
      prompt = title,
      format_item = opts.format_item,
    }, function(item, idx)
      -- vim.ui.select signals cancellation as `nil`; translate it so both
      -- paths route cancellation to on_cancel and never hand on_select nil.
      if item == nil then
        cancel()
      elseif on_select then
        on_select(item, idx)
      end
    end)
    delegating = false
    if not ok then
      error(err, 0)
    end
    return nil
  end

  -- The chooser displays plain strings, pre-rendered here so the chosen row
  -- maps back to the original item by index -- callers keep passing raw
  -- items, as with vim.ui.select. A "rich" item (table with `.lines`, for
  -- per-span custom highlights -- see UI-KIT-CONCEPT.md §13b) passes straight
  -- through unrendered instead: the chooser already knows how to lay those
  -- out itself. (Rich items are incompatible with `respect_override`'s
  -- foreign-picker delegation above, which only understands plain values --
  -- not a concern for any current caller, none of which combine the two.)
  local display = {}
  for i, item in ipairs(items) do
    if type(item) == "table" and type(item.lines) == "table" then
      display[i] = item
    else
      display[i] = display_line(item, opts.format_item)
    end
  end

  local chose = false
  local surf = chooser.open({
    items = display,
    on_select = function(_, idx_or_idxs)
      chose = true
      if not on_select then
        return
      end
      if multi then
        local mapped = {}
        for i, idx in ipairs(idx_or_idxs) do
          mapped[i] = items[idx]
        end
        on_select(mapped, idx_or_idxs)
      else
        on_select(items[idx_or_idxs], idx_or_idxs)
      end
    end,
    multi_select = multi,
    title = title,
    relative = opts.relative,
    theme = opts.theme,
    width = opts.width,
    height = opts.height,
    initial_index = opts.initial_index,
  })

  if not surf then
    cancel()
    return nil
  end

  if on_cancel then
    -- The chooser closes the surface BEFORE invoking on_select (submit()
    -- calls close(), then the callback), so on_close alone cannot tell a
    -- dismissal from a selection. Defer one tick to let a real selection
    -- flip `chose` first.
    surf:on_close(function()
      vim.schedule(function()
        if not chose then
          cancel()
        end
      end)
    end)
  end

  return surf
end

return M
