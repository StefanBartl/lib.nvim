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
--- cascade.nvim's word_cycle) call `vim.ui.select` directly instead of
--- kit.select specifically to respect the user's configured picker backend
--- -- `respect_override = true` gets that same behavior plus kit's nicer
--- default chooser for free when nothing else is installed. See
--- docs/ROADMAP/personal/lib_nvim/ui_kit_migration.md §2 for the audit.

local chooser = require("lib.nvim.ui.kit.chooser")

local M = {}

---Detect whether vim.ui.select is still Neovim's own builtin implementation.
---@return boolean overridden
local function is_overridden()
  local ok, info = pcall(debug.getinfo, vim.ui.select, "S")
  if not ok or not info or not info.source then
    return false
  end
  local src = info.source:gsub("\\", "/")
  return not src:match("/vim/ui%.lua$")
end

--- Open a list chooser.
---@param opts table  # { selection|items, on_select, message|title, format_item?, multi, relative, theme, width, height, respect_override? }
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local items = opts.selection or opts.items or {}
  ---@type fun(item: any, idx: any)
  local on_select = opts.on_select or function(_, _) end
  local multi = opts.multi or opts.multi_select or false

  if opts.respect_override and is_overridden() then
    vim.ui.select(items, {
      prompt = opts.title or opts.message,
      format_item = opts.format_item,
    }, on_select)
    return nil
  end

  -- Pre-format into plain display strings for the chooser (it only ever
  -- shows what it's given), remapping back to the original item by index in
  -- on_select -- a no-op remap when format_item is omitted, since `display`
  -- is then just `items` itself.
  local display = items
  if type(opts.format_item) == "function" then
    display = {}
    for i, item in ipairs(items) do
      display[i] = opts.format_item(item)
    end
  end

  return chooser.open({
    items = display,
    on_select = function(_, idx_or_idxs)
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
    title = opts.title or opts.message,
    relative = opts.relative,
    theme = opts.theme,
    width = opts.width,
    height = opts.height,
  })
end

return M
