---@module 'lib.nvim.ui.list'
--- Quickfix and location lists: the three lines everyone writes, written once.
---@description
--- Building the entries is the plugin's job and stays there. What repeats
--- across every plugin is the *last* step -- hand the entries to Vim, give the
--- list a title, open the window -- and it repeats inconsistently, in ways that
--- are invisible until they bite:
---
--- **The stack.** `setqflist(items, "r")` **replaces the current list**;
--- `setqflist({}, " ", {...})` **pushes a new one**. Only the second keeps
--- `:colder`/`:cnewer` history intact, so a plugin using `"r"` silently
--- destroys whatever the user had open. Both idioms were in use side by side,
--- and nothing in either call reads as a decision. Here it is one:
--- `action` defaults to `" "`, and `"r"` is something a caller asks for --
--- for a list it is *refreshing*, which is the one case where replacing is
--- right.
---
--- **The title.** `setqflist(items, "r")` cannot carry one, hence the widespread
--- second call `setqflist({}, "a", { title = ... })` -- an append of nothing,
--- purely to attach a string. One call does both.
---
--- **The focus.** `:copen` moves the cursor into the list. Sometimes that is
--- what you want (you are about to walk the entries); sometimes the list is
--- meant to be read *alongside* the buffer it describes. `focus` makes that a
--- parameter instead of an accident. The default is `"list"` -- what bare
--- `:copen` does -- so this module never changes behaviour behind a caller's
--- back.
---
--- **The empty case.** Opening a list window with nothing in it tells the user
--- nothing and steals half the screen. `open = "auto"` skips the window when
--- there are no entries; the list itself is still set, so an empty result
--- clears a stale one rather than leaving yesterday's findings standing.
---
--- Not in scope: filtering, formatting, or navigation. `vim.diagnostic` has its
--- own list functions with their own severity handling -- those are a different
--- API and are not wrapped here.
---
--- ```lua
--- local list = require("lib.nvim.ui.list")
---
--- list.qf(items, "myplugin: broken links")
--- list.qf(items, "myplugin: matches", { focus = "source", open = "auto" })
--- list.loc(items, "myplugin: this buffer")
--- list.set({ items = items, title = t, action = "r", open = false }) -- refresh in place
--- ```

---@class Lib.UI.List
local M = {}

--- The window whose location list is meant, or `nil` for the quickfix list.
---@param loclist boolean|integer|nil
---@return integer|nil
local function loc_win(loclist)
  if loclist == true then
    return 0
  end
  if type(loclist) == "number" then
    return loclist
  end
  return nil
end

--- Set a quickfix or location list, and optionally open it.
---@param opts Lib.UI.List.Opts|nil
---@return integer count Number of entries placed.
function M.set(opts)
  opts = opts or {}
  local items = opts.items or {}
  local action = opts.action or " "
  local what = { title = opts.title, items = items }
  local win = loc_win(opts.loclist)

  if win then
    vim.fn.setloclist(win, {}, action, what)
  else
    vim.fn.setqflist({}, action, what)
  end

  local open = opts.open
  if open == nil then
    open = true
  elseif open == "auto" then
    open = #items > 0
  end
  if not open then
    return #items
  end

  local from = vim.api.nvim_get_current_win()

  -- `:lopen` acts on the *current* window's location list, so a list set for
  -- some other window can only be shown by standing in that window first.
  if win and win ~= 0 and win ~= from and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_set_current_win, win)
  end

  local cmd = win and "lopen" or "copen"
  if opts.height then
    cmd = cmd .. " " .. tostring(opts.height)
  end
  -- `silent!` because both commands raise when there is no list to show
  -- (E776), and a failed *open* is never worth an error message on top of a
  -- result the caller already has in hand.
  vim.cmd("silent! " .. cmd)

  if opts.focus == "source" and vim.api.nvim_win_is_valid(from) then
    pcall(vim.api.nvim_set_current_win, from)
  end

  return #items
end

--- `M.set` for the quickfix list, with the two arguments that are always given
--- moved to the front.
---@param items Lib.UI.List.Item[]
---@param title string|nil
---@param opts Lib.UI.List.Opts|nil Everything else; a non-nil `title` here wins over `opts.title`.
---@return integer count
function M.qf(items, title, opts)
  local o = vim.tbl_extend("force", opts or {}, { items = items, title = title })
  o.loclist = nil
  return M.set(o)
end

--- `M.set` for a location list. Defaults to the current window; pass
--- `opts.loclist = <winid>` for another one.
---@param items Lib.UI.List.Item[]
---@param title string|nil
---@param opts Lib.UI.List.Opts|nil
---@return integer count
function M.loc(items, title, opts)
  local o = vim.tbl_extend("force", opts or {}, { items = items, title = title })
  if o.loclist == nil or o.loclist == false then
    o.loclist = true
  end
  return M.set(o)
end

return M
