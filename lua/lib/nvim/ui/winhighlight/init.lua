---@module 'lib.nvim.ui.winhighlight'
--- Read, merge and write `winhighlight` without clobbering what is already
--- there.
---
--- `winhighlight` is a comma-separated list of `from:to` group mappings on a
--- window. Two things make it awkward enough that most callers get it
--- slightly wrong:
---
---   * **It is shared.** A window may already carry mappings another plugin
---     (or the user) put there. Assigning the option outright silently
---     discards them, which is what `hover.nvim` and `reposcope.nvim` were
---     doing, and what `filetree.nvim`'s cursor-hide feature wrote its own
---     merge-and-strip pair of helpers to avoid.
---   * **A malformed entry throws `E5248`**, and the throw happens at the
---     `nvim_set_option_value` call, far from whatever built the string.
---
--- So this module parses defensively, drops entries it cannot vouch for,
--- and offers the operation callers actually want -- read, merge, write --
--- as one call.
---
--- Lifted out of `my.nvim`'s `hl_config.utils.winhighlight`, which was the
--- only validated implementation in the fleet and could not be reached from
--- outside that plugin (cross-feature report, finding C2).
---
--- **One behaviour deliberately differs from that original.** It validated
--- group names as `^[%w_]+$`, which silently dropped every mapping to a
--- Tree-sitter capture: `Normal:@comment` parses to nothing under that rule.
--- Neovim accepts `@`, `.` and `-` in a highlight group name -- verified
--- against a real window, not assumed -- so the charset here allows them.
--- What it still rejects is the empty string and anything containing `,` or
--- `:`, which are the two characters that would corrupt the list format
--- itself.
---
---   local wh = require("lib.nvim.ui.winhighlight")
---
---   wh.update(win, { Normal = "NormalFloat", FloatBorder = "FloatBorder" })
---   wh.remove(win, "Cursor")
---   local current = wh.parse(wh.get(win))

local M = {}

--- Characters allowed in a group name on either side of the colon.
---
--- `%w`, `_`, `.`, `@` and `-`: everything Neovim accepts, minus the two
--- separators (`,` and `:`) that would break the list format.
local GROUP = "^[%w_%.@%-]+$"

--- One `from:to` mapping.
---@class Lib.UI.Winhighlight.Pair
---@field from string
---@field to string

--- Split a `winhighlight` value into validated pairs.
---
--- Entries that do not parse are dropped rather than raised: the input is
--- typically whatever was already on the window, this module did not write
--- it, and refusing to work because a third party left something odd there
--- would be worse than ignoring it.
---@param wh string|nil
---@return Lib.UI.Winhighlight.Pair[]
function M.parse(wh)
  local res = {}

  if type(wh) ~= "string" or wh == "" then
    return res
  end

  for item in wh:gmatch("[^,]+") do
    local t = vim.trim(item)
    local from, to = t:match("^([^:]+):([^:]+)$")
    if from and to and from:match(GROUP) and to:match(GROUP) then
      res[#res + 1] = { from = from, to = to }
    end
  end

  return res
end

--- Serialize pairs back into a `winhighlight` value.
---
--- Re-validates on the way out. Callers build pair lists by hand, and the
--- cost of one pattern match per entry is nothing next to an `E5248` raised
--- from somewhere else entirely.
---@param entries Lib.UI.Winhighlight.Pair[]
---@return string
function M.serialize(entries)
  local out = {}
  for i = 1, #entries do
    local p = entries[i]
    if type(p.from) == "string" and type(p.to) == "string" then
      if p.from:match(GROUP) and p.to:match(GROUP) then
        out[#out + 1] = p.from .. ":" .. p.to
      end
    end
  end
  return table.concat(out, ",")
end

--- Merge `new_pairs` into `wh`. New mappings win; everything else is kept.
---@param wh string|nil # current value
---@param new_pairs table<string, string> # from -> to
---@return string
function M.merge(wh, new_pairs)
  local existing = M.parse(wh)
  local seen, out = {}, {}

  for from, to in pairs(new_pairs) do
    if type(from) == "string" and type(to) == "string" then
      if from:match(GROUP) and to:match(GROUP) then
        out[#out + 1] = { from = from, to = to }
        seen[from] = true
      end
    end
  end

  for i = 1, #existing do
    local p = existing[i]
    if not seen[p.from] then
      out[#out + 1] = p
    end
  end

  return M.serialize(out)
end

--- Set or remove a single mapping. `to = nil` removes it.
---@param wh string|nil
---@param from string
---@param to string|nil
---@return string
function M.set_pair(wh, from, to)
  local existing = M.parse(wh)
  local out = {}

  for i = 1, #existing do
    if existing[i].from ~= from then
      out[#out + 1] = existing[i]
    end
  end

  if type(to) == "string" and to ~= "" then
    out[#out + 1] = { from = from, to = to }
  end

  return M.serialize(out)
end

--- A window's current `winhighlight`, or `""` when the window is gone.
---@param win integer
---@return string
function M.get(win)
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end
  local ok, value = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
  if not ok or type(value) ~= "string" then
    return ""
  end
  return value
end

--- Write `wh` to a window.
---@param win integer
---@param wh string
---@return boolean success
function M.apply(win, wh)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return (pcall(vim.api.nvim_set_option_value, "winhighlight", wh, { scope = "local", win = win }))
end

--- Read, merge, write -- the operation every hand-rolled call site in this
--- fleet was performing in three or four lines of its own.
---@param win integer
---@param new_pairs table<string, string> # from -> to
---@return boolean success
function M.update(win, new_pairs)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return M.apply(win, M.merge(M.get(win), new_pairs))
end

--- Drop one or more mappings by their `from` group, leaving the rest alone.
---
--- The detach half of `update`: a plugin that added `Cursor:MyHidden` on
--- focus has to take exactly that back out on blur, without disturbing
--- whatever else the window carries.
---@param win integer
---@param from string|string[]
---@return boolean success
function M.remove(win, from)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local drop = {}
  if type(from) == "string" then
    drop[from] = true
  else
    for _, name in ipairs(from) do
      drop[name] = true
    end
  end

  local kept = {}
  for _, p in ipairs(M.parse(M.get(win))) do
    if not drop[p.from] then
      kept[#kept + 1] = p
    end
  end

  return M.apply(win, M.serialize(kept))
end

return M
