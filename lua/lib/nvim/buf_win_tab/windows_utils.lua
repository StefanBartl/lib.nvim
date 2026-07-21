---@module 'lib.nvim.buf_win_tab.windows_utils'
--- Utility library to inspect buffers, tabs and windows on Windows (also works on Linux/macOS).

---FIX: LSP

local notify = require("lib.nvim.notify").create("[lib.nvim.buf_win_tab.windows_utils]")

local M = {}

-- Local helpers and types -----------------------------------------------------

-- Detect platform to allow any small Windows-specific behavior if needed.
---@return boolean
local function is_windows()
  -- Return true when running on Windows (MSYS/Cygwin/Windows native)
  local ok, uname = pcall(vim.loop.os_uname)
  if not ok or not uname or not uname.sysname then
    return false
  end
  local sys = tostring(uname.sysname)
  return sys:match("Windows") ~= nil or sys:match("MSYS") ~= nil or sys:match("CYGWIN") ~= nil
end

-- Small helper to safely get buffer info from vim.fn.getbufinfo with optional fields.
---@param opts table|nil
---@return table[] list
local function getbufinfo(opts)
  -- opts is passed through to getbufinfo; ensure it is a table or nil
  if opts == nil then
    opts = {}
  end
  -- Use pcall to avoid throwing errors in unusual environments
  local ok, res = pcall(vim.fn.getbufinfo, opts)
  if not ok then
    return {}
  end
  return res
end

-- PUBLIC WINDOWS UTILS API -------------------------------------------------

-- Get info for all listed buffers and return their count.
---@return integer
function M.count_listed_buffers()
  ---@type table[]
  local listed = getbufinfo({ buflisted = 1 })
  -- Debug notify; caller can remove or replace with logging.
  notify.debug("Listed buffer: " .. tostring(#listed))
  return #listed
end

-- Return a table of basic buffer metadata for all buffers (listed and unlisted).
---@return table[] buffers
function M.list_all_buffers_info()
  ---@type table[]
  local bufs = getbufinfo({ bufnr = 0 }) -- getbufinfo() with no args returns all buffers; some neovim builds require arg
  if #bufs == 0 then
    -- Fallback: call without args
    bufs = getbufinfo(nil)
  end

  local out = {}
  for i = 1, #bufs do
    local b = bufs[i]
    -- Normalize fields that might be nil
    local entry = {
      bufnr = b.bufnr or b.bufnr or -1,
      name = b.name ~= "" and b.name or ("[No Name:" .. tostring(b.bufnr or -1) .. "]"),
      listed = (b.listed == 1 or b.buflisted == 1) and true or false,
      loaded = b.loaded == 1 or false,
      changed = b.changed == 1 or false,
      filetype = (b.variables and b.variables.ft)
        or vim.api.nvim_get_option_value("filetype", { buf = b.bufnr or -1 })
        or "",
      buftype = b.buftype or vim.api.nvim_get_option_value("buftype", { buf = b.bufnr or -1 }) or "",
      modified = vim.api.nvim_get_option_value("modified", { buf = b.bufnr or -1 }),
      size = b.size or 0,
    }
    out[#out + 1] = entry
  end
  return out
end

-- Return a list of buffer ids for all listed buffers.
---@return integer[] buf_ids
function M.get_listed_buffer_ids()
  ---@type table[]
  local listed = getbufinfo({ buflisted = 1 })
  ---@type integer[]
  local ids = {}
  for i = 1, #listed do
    ids[i] = listed[i].bufnr
  end
  return ids
end

-- Return buffer ids grouped by filetype. Table keys are filetype strings.
---@return table<string, integer[]> grouped
function M.get_buffers_grouped_by_filetype()
  local infos = M.list_all_buffers_info()
  ---@type table<string, integer[]>
  local grouped = {}
  for i = 1, #infos do
    local info = infos[i]
    local ft = info.filetype ~= "" and info.filetype or "[no_ft]"
    if grouped[ft] == nil then
      grouped[ft] = { [1] = info.bufnr } -- initialize with known small size pattern
    else
      grouped[ft][#grouped[ft] + 1] = info.bufnr
    end
  end
  return grouped
end

-- Get info for the current buffer (id, name, filetype, listed, modified, buftype).
---@return table info
function M.get_current_buffer_info()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok then
    name = ""
  end
  local info = {
    bufnr = bufnr,
    name = name ~= "" and name or ("[No Name:" .. tostring(bufnr) .. "]"),
    listed = vim.fn.buflisted(bufnr) == 1,
    filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
    buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr }),
    modified = vim.api.nvim_get_option_value("modified", { buf = bufnr }),
  }
  return info
end

-- Return buffers visible in a given tabpage (or current tabpage if nil).
---@param tabnr? integer
---@return integer[] buf_ids
function M.get_tabpage_buffers(tabnr)
  tabnr = tabnr or vim.api.nvim_get_current_tabpage()
  ---@type integer[]
  local out = {}
  -- Iterate windows in tabpage
  local wins = vim.api.nvim_tabpage_list_wins(tabnr)
  for i = 1, #wins do
    local w = wins[i]
    local b = vim.api.nvim_win_get_buf(w)
    -- push if not already present
    local found = false
    for j = 1, #out do
      if out[j] == b then
        found = true
        break
      end
    end
    if not found then
      out[#out + 1] = b
    end
  end
  return out
end

-- Format a compact, human-readable report of buffers, grouped by filetype.
---@return string
function M.format_buffers_report()
  local infos = M.list_all_buffers_info()
  local lines = { [1] = "Buffers report:" }
  for i = 1, #infos do
    local info = infos[i]
    local line = string.format(
      "  #%d  listed=%s  mod=%s  ft=%s  bt=%s  size=%d  name=%s",
      info.bufnr,
      tostring(info.listed),
      tostring(info.modified),
      info.filetype ~= "" and info.filetype or "-",
      info.buftype ~= "" and info.buftype or "-",
      info.size or 0,
      info.name
    )
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

-- Aggregate function: collect many pieces of state and return a table.
---@return table
function M.collect_all_state()
  local state = {
    platform = is_windows() and "windows" or "unix",
    listed_count = M.count_listed_buffers(),
    listed_ids = M.get_listed_buffer_ids(),
    buffers_by_filetype = M.get_buffers_grouped_by_filetype(),
    current = M.get_current_buffer_info(),
    tabpage_buffers = M.get_tabpage_buffers(),
    only_nonfile_listed = M.only_nonfile_listed_buffers(),
  }
  return state
end

-- Convenience function: print aggregated state nicely to :messages (or return string if silent=true).
---@param silent boolean|nil if true, return the string instead of notifying
---@return string|nil
function M.show_aggregated_state(silent)
  local st = M.collect_all_state()
  local lines = { [1] = string.format("Platform: %s", st.platform) }
  lines[#lines + 1] = string.format("Listed buffers: %d", st.listed_count)
  lines[#lines + 1] = "Listed IDs: " .. table.concat(st.listed_ids or {}, ", ")
  lines[#lines + 1] = "Tabpage visible buffers: " .. table.concat(st.tabpage_buffers or {}, ", ")
  lines[#lines + 1] = "Only non-file listed buffers: " .. tostring(st.only_nonfile_listed)
  lines[#lines + 1] = "Current buffer: #" .. tostring(st.current.bufnr) .. " (" .. st.current.filetype .. ")"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Detailed buffer list:"
  local buflines = vim.split(M.format_buffers_report(), "\n")
  for i = 1, #buflines do
    lines[#lines + 1] = buflines[i]
  end
  local out = table.concat(lines, "\n")
  if silent then
    return out
  else
    -- Use vim.schedule to avoid calling notify during an API-critical moment.
    vim.schedule(function()
      notify.info(out)
    end)
    return nil
  end
end

---Collect window report for current or specified window
---@param winid integer|nil
---@return { textual: string[], raw: table }
function M.collect_win_report(winid)
  winid = winid or vim.api.nvim_get_current_win()
  local api = vim.api

  if not api.nvim_win_is_valid(winid) then
    return {
      textual = { string.format("Window %d is invalid", winid) },
      raw = { valid = false, winid = winid }
    }
  end

  local report = { textual = {}, raw = {} }

  -- Basic window info
  local ok_buf, bufnr = pcall(api.nvim_win_get_buf, winid)
  local ok_cursor, cursor = pcall(api.nvim_win_get_cursor, winid)
  local ok_config, config = pcall(api.nvim_win_get_config, winid)

  report.raw.winid = winid
  report.raw.bufnr = ok_buf and bufnr or nil
  report.raw.cursor = ok_cursor and cursor or nil
  report.raw.config = ok_config and config or nil

  table.insert(report.textual, string.format("=== Window Report: %d ===", winid))
  table.insert(report.textual, string.format("Valid: %s", "true"))
  table.insert(report.textual, string.format("Buffer: %s", ok_buf and bufnr or "ERROR"))

  if ok_buf and bufnr then
    local ok_name, name = pcall(api.nvim_buf_get_name, bufnr)
    local ok_ft, ft = pcall(function() return vim.bo[bufnr].filetype end)
    local ok_bt, bt = pcall(function() return vim.bo[bufnr].buftype end)

    report.raw.buf_name = ok_name and name or nil
    report.raw.filetype = ok_ft and ft or nil
    report.raw.buftype = ok_bt and bt or nil

    table.insert(report.textual, string.format("  Name: %s", ok_name and name or "ERROR"))
    table.insert(report.textual, string.format("  Filetype: %s", ok_ft and ft or "ERROR"))
    table.insert(report.textual, string.format("  Buftype: %s", ok_bt and bt or "ERROR"))
  end

  if ok_cursor then
    table.insert(report.textual, string.format("Cursor: [%d, %d]", cursor[1], cursor[2]))
  end

  -- Window options
  local win_opts = {
    "number", "relativenumber", "wrap", "cursorline",
    "winbar", "statusline", "signcolumn", "foldcolumn"
  }

  table.insert(report.textual, "Window Options:")
  for _, opt in ipairs(win_opts) do
    local ok, val = pcall(function() return vim.wo[winid][opt] end)
    if ok then
      report.raw[opt] = val
      table.insert(report.textual, string.format("  %s: %s", opt, tostring(val)))
    end
  end

  -- Window variables
  local win_vars = vim.w[winid] or {}
  if next(win_vars) then
    table.insert(report.textual, "Window Variables:")
    for k, v in pairs(win_vars) do
      report.raw.vars = report.raw.vars or {}
      report.raw.vars[k] = v
      table.insert(report.textual, string.format("  %s: %s", k, tostring(v)))
    end
  end

  -- Window configuration
  if ok_config then
    table.insert(report.textual, "Window Config:")
    table.insert(report.textual, string.format("  Relative: %s", config.relative or "editor"))
    table.insert(report.textual, string.format("  Width: %s", config.width or "full"))
    table.insert(report.textual, string.format("  Height: %s", config.height or "full"))
    table.insert(report.textual, string.format("  Focusable: %s", tostring(config.focusable)))
    if config.zindex then
      table.insert(report.textual, string.format("  Z-Index: %d", config.zindex))
    end
  end

  return report
end


---@type Lib.BufWinTab.WindowsUtils
return M
