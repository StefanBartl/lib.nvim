---@module 'lib.nvim.buf_win_tab.capture'
---Deterministic capture of buffers and windows created by Ex commands.
---Supports async creation, timeouts, multi-object capture and User events.

local notify = require("lib.nvim.notify").create("[lib.nvim.buf_win_tab.capture]")

local api = vim.api
local uv = vim.uv

local M = {}

-- Default configuration
local DEFAULT_TIMEOUT = 300
local DEFAULT_INTERVAL = 20

---Capture current editor state
---@return table<integer, true>, table<integer, true>
local function snapshot_state()
  local wins = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    wins[win] = true
  end

  local bufs = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    bufs[buf] = true
  end

  return wins, bufs
end

---Compute delta between two snapshots
---@param before table<integer, true>
---@param after integer[]
---@return integer[]
local function delta(before, after)
  local out = {}
  for _, id in ipairs(after) do
    if not before[id] then
      out[#out + 1] = id
    end
  end
  return out
end

---Filter windows to only include focusable, valid content windows
---@param wins integer[]
---@return integer[]
local function filter_focusable_windows(wins)
  local focusable = {}

  for _, win in ipairs(wins) do
    if api.nvim_win_is_valid(win) then
      local ok_config, config = pcall(api.nvim_win_get_config, win)

      if ok_config then
        -- Only include windows that are:
        -- 1. Not border/title windows (relative ~= "win")
        -- 2. Have actual content (width > 1, height > 1)
        -- 3. Not hidden
        local is_content_win = config.relative ~= "win"
          and config.width > 1
          and config.height > 1
          and not config.hide

        if is_content_win then
          focusable[#focusable + 1] = win
        end
      end
    end
  end

  return focusable
end

---Apply tags to buffers and windows
---@param result BufWinCapture.Results
---@param tag BufWinCapture.Tag|nil
local function apply_tags(result, tag)
  if not tag then
    return
  end

  if tag.buf then
    for _, buf in ipairs(result.bufs) do
      vim.b[buf].custom_tag = tag.buf
    end
  end

  if tag.win then
    for _, win in ipairs(result.wins) do
      vim.w[win].custom_tag = tag.win
    end
  end
end

---Emit User autocommand
---@param result BufWinCapture.Results
local function emit_event(result)
  api.nvim_exec_autocmds("User", {
    pattern = "BufWinCapture",
    data = result,
  })
end

--- Safely stop and close a uv timer exactly once
---@param t uv.uv_timer_t
local function safe_close_timer(t)
  -- stop() is always safe and idempotent
  t:stop()

  -- close() must only be called once
  if not uv.is_closing(t) then
    t:close()
  end
end

---Public API: capture buffers and windows created by an Ex command
---@param cmd string
---@param opts BufWinCapture.Opts|nil
---@param cb fun(result: BufWinCapture.Results)|nil
---@return BufWinCapture.Results|nil
function M.capture(cmd, opts, cb)
  if type(cmd) ~= "string" then
    notify.error("[lib.nvim.buf_win_tab.capture] cmd must be a string")
    return nil
  end

  opts = opts or {}

  local timeout = opts.timeout or DEFAULT_TIMEOUT
  local interval = opts.interval or DEFAULT_INTERVAL

  local wins_before, bufs_before = snapshot_state()

  -- Execute command
  vim.cmd(cmd)

  local start = uv.now()
  local timer = uv.new_timer()
  if not timer then
    notify.error("timer is nil")
    return nil
  end

  ---@cast timer uv.uv_timer_t

  local function poll()
    local wins_after = api.nvim_list_wins()
    local bufs_after = api.nvim_list_bufs()

    local new_wins = delta(wins_before, wins_after)
    local new_bufs = delta(bufs_before, bufs_after)

    -- CRITICAL: Filter to only focusable content windows
    new_wins = filter_focusable_windows(new_wins)

    if #new_wins > 0 or #new_bufs > 0 then
      safe_close_timer(timer)

      local result = {
        wins = new_wins,
        bufs = new_bufs,
      }

      apply_tags(result, opts.tag)

      if opts.emit_event then
        emit_event(result)
      end

      if cb then
        cb(result)
      end

      return
    end

    if uv.now() - start >= timeout then
      safe_close_timer(timer)

      local result = {
        wins = {},
        bufs = {},
      }

      if opts.emit_event then
        emit_event(result)
      end

      if cb then
        cb(result)
      end
    end
  end

  timer:start(0, interval, vim.schedule_wrap(poll))

  -- Async path returns nothing immediately
  if cb then
    return nil
  end

  -- Sync fallback: block until timeout
  local deadline = uv.now() + timeout
  while uv.now() < deadline do
    vim.wait(interval)
    local wins_after = api.nvim_list_wins()
    local bufs_after = api.nvim_list_bufs()

    local new_wins = delta(wins_before, wins_after)
    local new_bufs = delta(bufs_before, bufs_after)

    -- CRITICAL: Filter to only focusable content windows
    new_wins = filter_focusable_windows(new_wins)

    if #new_wins > 0 or #new_bufs > 0 then
      local result = {
        wins = new_wins,
        bufs = new_bufs,
      }

      apply_tags(result, opts.tag)

      if opts.emit_event then
        emit_event(result)
      end

      return result
    end
  end

  return {
    wins = {},
    bufs = {},
  }
end

---@type Lib.BufWinTab.Capture
return M
