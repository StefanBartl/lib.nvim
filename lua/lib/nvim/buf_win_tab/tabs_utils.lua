---@module 'lib.nvim.buf_win_tab.tabs_utils'
--- Small helper module to inspect and format tabpage information.
--- Works on all platforms including Windows; no external dependencies.

local notify = require("lib.nvim.notify").create("[lib.nvim.buf_win_tab.tabs_utils]")

local M = {}

-- Types ----------------------------------------------------------------------

-- Collect a TabInfo for a given tabpage object.
---@param tabpage userdata
---@return TabInfo
local function collect_tab_info(tabpage)
  local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
  ---@type integer[]
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  ---@type integer[]
  local bufs = {}
  for _, w in ipairs(wins) do
    local b = vim.api.nvim_win_get_buf(w)
    bufs[b] = bufs[b] or 0
    bufs[b] = bufs[b] + 1
  end

  -- convert bufs map to array of unique buffer numbers
  local unique_bufs = {}
  for b, _ in pairs(bufs) do
    table.insert(unique_bufs, b)
  end

  local cur_win = vim.api.nvim_tabpage_get_win(tabpage)
  local cur_buf = vim.api.nvim_win_get_buf(cur_win)

  return {
    tabnr = tabnr,
    tabpage = tabpage,
    wins = wins,
    bufs = unique_bufs,
    current_win = cur_win,
    current_buf = cur_buf,
  }
end

-- Return list of TabInfo for all tabpages.
---@return TabInfo[]
function M.list_tabs()
  local tps = vim.api.nvim_list_tabpages()
  ---@type TabInfo[]
  local out = {}
  for _, tp in ipairs(tps) do
    table.insert(out, collect_tab_info(tp))
  end
  return out
end

-- Format a single tab info into a concise one-line description.
---@param info TabInfo
---@return string
function M.format_tab_one_line(info)
  local bufs_count = #info.bufs
  local wins_count = #info.wins
  local cur_buf = info.current_buf or 0
  return string.format("tab=%d wins=%d bufs=%d cur_buf=%d", info.tabnr, wins_count, bufs_count, cur_buf)
end

-- Pretty-print tabs to messages (vim.notify).
---@param tabs TabInfo[]?
function M.print_tabs(tabs)
  tabs = tabs or M.list_tabs()
  if #tabs == 0 then
    notify.info("No tabpages")
    return
  end
  for _, t in ipairs(tabs) do
    local line = M.format_tab_one_line(t)
    notify.debug(line)
    -- Optionally print buffer names per tab for more detail
    local names = {}
    for _, b in ipairs(t.bufs) do
      table.insert(
        names,
        vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":~:.") ~= ""
            and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":~:.")
          or "[no-name]"
      )
    end
    notify.debug("  bufs: " .. table.concat(names, ", "))
  end
end

-- Find the tab that contains the currently active window.
---@return TabInfo?
function M.get_current_tab()
  local curtp = vim.api.nvim_get_current_tabpage()
  if not curtp then
    return nil
  end
  return collect_tab_info(curtp)
end

-- Return tab with a given tab number (or nil).
---@param tabnr integer
---@return TabInfo?
function M.get_tab_by_number(tabnr)
  for _, t in ipairs(M.list_tabs()) do
    if t.tabnr == tabnr then
      return t
    end
  end
  return nil
end

-- Helper: return true if there is only one tab open.
---@return boolean
function M.is_single_tab()
  return #vim.api.nvim_list_tabpages() <= 1
end

-- Collector: returns a structured report for tabs (counts + summaries).
---@return table
function M.collect_report()
  local tabs = M.list_tabs()
  local lines = {}
  table.insert(lines, string.format("tab_count=%d", #tabs))
  for _, t in ipairs(tabs) do
    table.insert(lines, M.format_tab_one_line(t))
  end
  return {
    count = #tabs,
    tabs = tabs,
    textual = lines,
  }
end

---@type Lib.BufWinTab.TabsUtils
return M
