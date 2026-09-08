---@module 'lib.nvim.ui.kit.menu'
--- Menu component: an anchored action list. Each item pairs a label with a
--- callback; picking an item runs its callback. Built on the native chooser
--- (lib.nvim.ui.kit.chooser), so it inherits themed selection and the same
--- navigation (j/k/arrows, <CR>, <Esc>/q).
---
--- It accepts two item shapes, because it doubles as the native renderer for
--- `lib.nvim.contextmenu` (see that module's `renderer` option):
---
--- - the kit's own `{ label = "Do X", action = fn }`, and
--- - nvzone/menu's `{ name = "Do X", cmd = fn, rtxt = "<leader>x", hl = … }`,
---   including `{ name = "separator" }` dividers and nested fly-outs
---   (`{ name = "Git ▸", items = { … } }`, or `items = "gitsigns"` for one of
---   nvzone/menu's own `menus.*` tables).
---
--- Nesting is a **drill-down**, not a side-by-side fly-out: picking a nested
--- entry replaces the current list with its children (the chooser is a single
--- active instance). Every level below the top opens with a `◂ Back` entry,
--- and `<BS>` does the same thing from the keyboard — a menu reached by
--- <RightMouse> has to be leavable with the mouse too. That drill-down is
--- the one behavioural difference from nvzone/menu, which opens the child in
--- a second window beside the parent.

local chooser = require("lib.nvim.ui.kit.chooser")
local map = require("lib.nvim.bindings.keymap")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit.menu]")

local M = {}

--- Columns between a label and its right-aligned `rtxt` hint.
local RTXT_GAP = 3

--- Marker appended to an entry that opens a nested list. Plain Unicode, not
--- a Nerd Font glyph: a menu that has to render on any terminal is the wrong
--- place to require a patched font.
local SUBMENU_MARKER = " ▸"

--- Label of the entry that walks one level back up. It exists so the
--- drill-down is usable with the mouse, which `<BS>` alone is not.
local BACK_LABEL = "◂ Back"

--- Resolve an item's display label across both accepted shapes.
---@internal
---@param it any
---@return string
local function label_of(it)
  if type(it) ~= "table" then
    return tostring(it)
  end
  return tostring(it.label or it.name or it.text or "")
end

--- Resolve an item's nested children, following nvzone/menu's `items = "name"`
--- indirection into `menus.<name>`. Returns nil when the item is a leaf.
---@internal
---@param it any
---@return Lib.UI.Kit.MenuItem[]|nil
local function children_of(it)
  if type(it) ~= "table" then
    return nil
  end
  local items = it.items
  if type(items) == "string" then
    local ok, mod = pcall(require, "menus." .. items)
    if not ok or type(mod) ~= "table" then
      return nil
    end
    items = mod
  end
  if type(items) == "table" and #items > 0 then
    return items
  end
  return nil
end

--- Resolve an item's leaf action, normalizing nvzone/menu's Ex-command
--- strings into callables.
---@internal
---@param it any
---@return fun()|nil
local function action_of(it)
  if type(it) ~= "table" then
    return nil
  end
  local action = it.action or it.cb or it.cmd
  if type(action) == "function" then
    return action
  end
  if type(action) == "string" then
    return function()
      vim.cmd(action)
    end
  end
  return nil
end

--- Whether the item is nvzone/menu's divider.
---@internal
---@param it any
---@return boolean
local function is_separator(it)
  return type(it) == "table" and it.name == "separator" and it.cmd == nil and it.items == nil
end

--- Width of the widest label, and of the widest `rtxt`, across `items`.
---@internal
---@param items any[]
---@return integer label_w, integer rtxt_w
local function measure(items)
  local label_w, rtxt_w = 0, 0
  for _, it in ipairs(items) do
    if not is_separator(it) then
      local l = vim.fn.strdisplaywidth(label_of(it) .. (children_of(it) and SUBMENU_MARKER or ""))
      label_w = math.max(label_w, l)
      local r = type(it) == "table" and it.rtxt or nil
      if r then
        rtxt_w = math.max(rtxt_w, vim.fn.strdisplaywidth(tostring(r)))
      end
    end
  end
  return label_w, rtxt_w
end

--- Build the chooser row for one item: the padded label, its `rtxt` hint
--- right-aligned in a fixed trailing column, and the highlight spans for
--- both. Separators become an inert divider line.
---@internal
---@param it any
---@param label_w integer
---@param rtxt_w integer
---@return Lib.UI.Kit.RichItem
local function row_of(it, label_w, rtxt_w)
  local total = label_w + (rtxt_w > 0 and (RTXT_GAP + rtxt_w) or 0)

  if is_separator(it) then
    return {
      lines = { string.rep("─", math.max(1, total)) },
      highlights = { { line = 0, hl_group = "KitBorder" } },
      selectable = false,
    }
  end

  local label = label_of(it) .. (children_of(it) and SUBMENU_MARKER or "")
  local line = label .. string.rep(" ", math.max(0, label_w - vim.fn.strdisplaywidth(label)))

  local highlights = {}
  local hl = type(it) == "table" and it.hl or nil
  if hl then
    highlights[#highlights + 1] = { line = 0, col_start = 0, col_end = #line, hl_group = hl }
  end

  local rtxt = type(it) == "table" and it.rtxt or nil
  if rtxt_w > 0 then
    rtxt = rtxt and tostring(rtxt) or ""
    local pad = RTXT_GAP + rtxt_w - vim.fn.strdisplaywidth(rtxt)
    local col_start = #line + pad
    line = line .. string.rep(" ", pad) .. rtxt
    if rtxt ~= "" then
      highlights[#highlights + 1] =
        { line = 0, col_start = col_start, col_end = #line, hl_group = "KitMuted" }
    end
  end

  return { lines = { line }, highlights = #highlights > 0 and highlights or nil }
end

--- Reopen the parent level, popping it off `stack`.
---@internal
---@param open_level fun(opts: table, items: any[], stack: table[])
---@param opts table
---@param stack table[]
local function go_back(open_level, opts, stack)
  local parent = stack[#stack]
  if not parent then
    return
  end
  chooser.close()
  local prev_stack = vim.list_extend({}, stack)
  prev_stack[#prev_stack] = nil
  vim.schedule(function()
    open_level(vim.tbl_extend("force", opts, { title = parent.title }), parent.items, prev_stack)
  end)
end

--- Open one level of the menu. `stack` carries the ancestors, so `<BS>`
--- and the back entry can reopen the parent list without the caller knowing
--- about nesting.
---@internal
---@param opts table
---@param raw_items any[]  # the level's own items, without the back entry
---@param stack table[]  # { { items = …, title = … }, … }, outermost first
---@return Lib.UI.Kit.Surface|nil
local function open_level(opts, raw_items, stack)
  -- Below the top level, the list gets a back entry of its own. `<BS>` alone
  -- would leave the drill-down unusable with the mouse -- and <RightMouse> is
  -- how this menu is opened in the first place. `raw_items` stays the version
  -- without it, so a level pushed onto the stack doesn't grow a second back
  -- entry when it is reopened.
  local items = raw_items
  if #stack > 0 then
    items = { { name = BACK_LABEL, __back = true }, { name = "separator" } }
    vim.list_extend(items, raw_items)
  end

  local label_w, rtxt_w = measure(items)

  local rows = {}
  for i, it in ipairs(items) do
    rows[i] = row_of(it, label_w, rtxt_w)
  end

  -- `mouse = true` is nvzone/menu's spelling for "anchor at the pointer";
  -- Neovim's own `relative = "mouse"` does exactly that, so it needs no
  -- coordinate arithmetic here.
  local relative = opts.relative or (opts.mouse and "mouse") or "cursor"

  local surf = chooser.open({
    items = rows,
    title = opts.title,
    theme = opts.theme,
    relative = relative,
    row = opts.row,
    col = opts.col,
    on_select = function(_, idx)
      local it = items[idx]
      if not it then
        return
      end
      if it.__back then
        -- The chooser already closed on submit; go_back reopens the parent.
        go_back(open_level, opts, stack)
        return
      end
      local nested = children_of(it)
      if nested then
        -- Drill down: the chooser closed on submit, so this reopens at the
        -- child level with the parent pushed onto the back stack.
        local next_stack = vim.list_extend({}, stack)
        next_stack[#next_stack + 1] = { items = raw_items, title = opts.title }
        vim.schedule(function()
          open_level(vim.tbl_extend("force", opts, { title = label_of(it) }), nested, next_stack)
        end)
        return
      end
      local action = action_of(it)
      if action then
        action()
      end
    end,
  })

  if surf and #stack > 0 then
    map("n", "<BS>", function()
      go_back(open_level, opts, stack)
    end, { buffer = surf.bufnr, nowait = true, desc = "kit.menu: back to parent menu" })
  end

  return surf
end

--- Open an action menu.
---@param opts Lib.UI.Kit.MenuOpts
---@return Lib.UI.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  local items = opts.items or {}
  if type(items) ~= "table" or #items == 0 then
    notify.error("menu: `items` is required and must be non-empty")
    return nil
  end
  return open_level(opts, items, {})
end

--- Close the menu if one is open (it shares the chooser's single instance).
function M.close()
  chooser.close()
end

--- Whether a menu (or any other chooser-backed component) is open.
---@return boolean
function M.is_open()
  return chooser.is_open()
end

return M
