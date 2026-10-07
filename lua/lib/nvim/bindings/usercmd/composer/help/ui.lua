---@module 'lib.nvim.bindings.usercmd.composer.help.ui'
--- Draws a `help.entries` result as a float: one row per option,
--- `option  description`, section headings between the groups. Built on
--- `lib.nvim.ui.kit.select` (themed chooser: j/k/arrows, <CR> picks,
--- <Esc>/q closes), so it looks and navigates like every other kit list.
---
--- It only draws and reports the pick; what a pick does to the command line
--- is `help`'s business.

local M = {}

--- Widest option column, so one long option does not push every description
--- off the screen.
local LABEL_MAX = 34

--- Share of the screen width the float may take.
local WIDTH_SHARE = 0.8

--- Marker after a group, which opens a further level of subcommands.
local GROUP_MARK = " ›"

---@internal
--- Pad `s` with spaces to display width `w`.
---@param s string
---@param w integer
---@return string
local function pad(s, w)
  local missing = w - vim.fn.strdisplaywidth(s)
  return missing > 0 and (s .. string.rep(" ", missing)) or s
end

---@internal
--- Cut `s` to at most `w` display cells, with an ellipsis.
---@param s string
---@param w integer
---@return string
local function clip(s, w)
  if vim.fn.strdisplaywidth(s) <= w then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(1, w - 1)) .. "…"
end

--- Rich chooser items for `entries`. Headings are dropped when there is only
--- one section (a lone "Subcommands" title says nothing).
---@param entries Lib.UserCmd.Composer.Help.Entry[]
---@return table[] items          # chooser items; each carries its `entry`
---@return integer|nil first      # index of the first pickable item
function M.build_items(entries)
  local headings = 0
  for _, e in ipairs(entries) do
    if e.kind == "heading" then
      headings = headings + 1
    end
  end
  local show_headings = headings > 1

  local label_w = 0
  for _, e in ipairs(entries) do
    if e.kind ~= "heading" then
      local text = e.label .. (e.kind == "group" and GROUP_MARK or "")
      label_w = math.max(label_w, vim.fn.strdisplaywidth(text))
    end
  end
  label_w = math.min(label_w, LABEL_MAX)
  -- The float never grows past this share of the screen; a longer
  -- description is cut with an ellipsis rather than pushing the float off it.
  local desc_budget = math.max(16, math.floor(vim.o.columns * WIDTH_SHARE) - label_w - 6)

  local items, first = {}, nil
  for _, e in ipairs(entries) do
    if e.kind == "heading" then
      if show_headings then
        items[#items + 1] = {
          lines = { " " .. e.label },
          highlights = { { line = 0, hl_group = "KitTitle" } },
          selectable = false,
          entry = e,
        }
      end
    else
      local label = clip(e.label .. (e.kind == "group" and GROUP_MARK or ""), label_w)
      local text = " " .. pad(label, label_w)
      local hls = { { line = 0, col_start = 1, col_end = #text, hl_group = "KitAccent" } }
      if e.desc and e.desc ~= "" then
        local gap = "  "
        local desc = clip((e.desc:gsub("[\r\n]+", " ")), desc_budget)
        hls[#hls + 1] = {
          line = 0,
          col_start = #text + #gap,
          col_end = #text + #gap + #desc,
          hl_group = "KitMuted",
        }
        text = text .. gap .. desc
      end
      items[#items + 1] = {
        lines = { text },
        highlights = hls,
        selectable = e.insert ~= nil,
        entry = e,
      }
      if e.insert and not first then
        first = #items
      end
    end
  end
  return items, first
end

--- Open the float.
---@param entries Lib.UserCmd.Composer.Help.Entry[]
---@param opts { title?: string, on_pick: fun(entry: Lib.UserCmd.Composer.Help.Entry), on_cancel?: fun() }
---@return boolean opened
function M.open(entries, opts)
  local items, first = M.build_items(entries)
  if not first then
    return false
  end
  local surf = require("lib.nvim.ui.kit.select").open({
    items = items,
    title = opts.title,
    relative = "editor",
    initial_index = first,
    on_select = function(item)
      if item and item.entry then
        opts.on_pick(item.entry)
      end
    end,
    on_cancel = opts.on_cancel,
  })
  return surf ~= nil
end

return M
