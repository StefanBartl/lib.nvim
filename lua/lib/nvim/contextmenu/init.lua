---@module 'lib.nvim.contextmenu'
--- Building blocks for nvzone/menu-shaped context-menu entries: a
--- self-gating item builder (`entry`/`group`/`submenu`) plus a mouse-trigger
--- binder (`bind_buffer`). Soft dependency throughout — `menu` (nvzone/menu)
--- is only `require()`d when a bound trigger actually fires, and a missing
--- install degrades to a single notify, never an error.
---
--- Two integration shapes this supports (see filetree.nvim and
--- markdown.nvim for the two live reference implementations):
---
--- "Owns its buffer" (a plugin-created UI: a tree, a dashboard, a list-view)
--- >lua
---   -- integrations/menu.lua
---   function M.items()
---     local out = {}
---     contextmenu.group(out,
---       contextmenu.entry(feature("x") ~= nil, "  Do X", do_x, "<leader>x")
---     )
---     return out
---   end
---
---   -- features/ui/context_menu/init.lua, on the plugin's own buffer
---   contextmenu.bind_buffer(bufnr, require("myplugin.integrations.menu").items)
--- <
--- "Contributes only" (acts on ordinary filetype-scoped buffers): the plugin
--- ships just `integrations/menu.lua` (`items`/`submenu`) with no trigger
--- code at all; a host (typically the user's own RightMouse dispatcher)
--- composes `submenu(...)` into its own menu for the relevant filetype.

require("lib.nvim.contextmenu.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.contextmenu]")

local M = {}

---@internal
--- Warn once per session that `menu` (nvzone/menu) isn't installed, when a
--- bound trigger fires with nothing to open it with.
local _warned_missing = false
local function warn_missing_once()
  if _warned_missing then return end
  _warned_missing = true
  notify.info("nvzone/menu not installed — context menu has nothing to open")
end

--- Build one entry, or nil when `available` is falsy — lets a caller write a
--- flat list of `entry(...)` calls and rely on `group`/`vim.tbl_filter` to
--- drop the gaps, instead of hand-writing `if` guards around every item.
---@param available any  Truthy to include the entry, falsy to omit it
---@param label string
---@param fn function     Called with no arguments when the entry is picked
---@param rtxt? string    Right-aligned hint text (usually a default keymap)
---@return Lib.ContextMenu.Item|nil
function M.entry(available, label, fn, rtxt)
  if not available then return nil end
  return { name = label, rtxt = rtxt, cmd = fn }
end

--- Append every non-nil argument to `out`, preceded by a separator when
--- `out` already holds entries and at least one argument survives. Mirrors
--- nvzone/menu's `{ name = "separator" }` convention.
---
--- Takes varargs, not a table: a table literal like `{ entry(...), nil,
--- entry(...) }` loses everything past the first gap under `ipairs`/`#`
--- (Lua doesn't define a length for a table with holes), silently dropping
--- later entries whenever an earlier one in the same group gates off.
--- Varargs don't have that problem — `select('#', ...)` counts every
--- position, nil or not — so call this as
--- `group(out, entry(...), entry(...), entry(...))`, unpacking a
--- pre-built list with `group(out, unpack(list))` if you already have one.
---@param out Lib.ContextMenu.Item[]
---@param ... Lib.ContextMenu.Item|nil
---@return boolean added  Whether anything from the arguments was appended
function M.group(out, ...)
  local n = select("#", ...)
  local compact = {}
  for i = 1, n do
    local item = select(i, ...)
    if item ~= nil then compact[#compact + 1] = item end
  end
  if #compact == 0 then return false end
  if #out > 0 then out[#out + 1] = { name = "separator" } end
  for _, item in ipairs(compact) do out[#out + 1] = item end
  return true
end

--- Wrap `items` as one nested fly-out entry (the "Lsp Actions ▸" shape).
--- Returns nil when `items` is empty, so callers can chain it straight into
--- a host's composed list without an extra emptiness check:
--- `vim.list_extend(composed, { contextmenu.submenu("  My Plugin", items) })`
--- would insert a stray nil — check the return instead, as in the usage
--- examples above.
---@param label string
---@param items Lib.ContextMenu.Item[]
---@return Lib.ContextMenu.Item|nil
function M.submenu(label, items)
  if type(items) ~= "table" or #items == 0 then return nil end
  return { name = label, items = items }
end

--- Bind a mouse trigger on `bufnr` that opens `get_items()` via nvzone/menu.
--- `menu` is soft-required at trigger time, not at bind time, so this is
--- safe to call unconditionally from a plugin's setup path even when
--- nvzone/menu isn't installed — the keymap just becomes a no-op (with one
--- session-wide notify) until it is.
---@param bufnr integer
---@param get_items fun():Lib.ContextMenu.Item[]
---@param opts? { keymap?: string, modes?: string[], mouse?: boolean, desc?: string }
function M.bind_buffer(bufnr, get_items, opts)
  opts = opts or {}
  local keymap = opts.keymap or "<RightMouse>"
  local modes = opts.modes or { "n", "v" }
  local mouse = opts.mouse ~= false

  vim.keymap.set(modes, keymap, function()
    local ok_menu, menu = pcall(require, "menu")
    if not ok_menu or type(menu.open) ~= "function" then
      warn_missing_once()
      return
    end

    local items = get_items()
    if type(items) ~= "table" or #items == 0 then return end

    menu.open(items, { mouse = mouse })
  end, {
    buffer = bufnr,
    silent = true,
    desc = opts.desc or "Context menu",
  })
end

return M
