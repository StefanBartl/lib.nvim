---@module 'lib.nvim.companion.client'
--- The companion side: runs in the SECOND Neovim (`nvim -u NONE --cmd "lua
--- require('lib.nvim.companion.client').start{...}"`), never in the main one.
---
--- It connects to the main instance, starts its own server, reports in
--- (`companion._attach`), shows what the main pushes (`render`, `set_title`)
--- in one read-only buffer and turns the configured keys into actions of the
--- main (`companion._action`). `q` quits. It leaves by itself when the main
--- is gone (`_detach` on the way out when the main is still there).
---
--- The one blocking request this side makes is `_attach`, before the main has
--- a channel to this instance; everything after that is a notification.

local M = {}

local MAIN = "lib.nvim.companion"
local LIVENESS_MS = 1000
local FLUSH_MS = 100

---@class Lib.Companion.ClientState
---@field main integer|nil # channel to the main instance
---@field id integer|nil
---@field buf integer|nil
---@field ns integer|nil
---@field title string
local S = { title = "Companion" }

---@param msg string
local function fail(msg)
  pcall(io.stderr.write, io.stderr, "lib.nvim.companion.client: " .. msg .. "\n")
  vim.cmd("qa!")
end

---@param code string
---@param args any[]
---@return boolean ok
---@return any result
local function call(code, args)
  if not S.main then
    return false, "not connected"
  end
  return pcall(vim.rpcrequest, S.main, "nvim_exec_lua", code, args)
end

---@param code string
---@param args any[]
local function notify(code, args)
  if S.main then
    pcall(vim.rpcnotify, S.main, "nvim_exec_lua", code, args)
  end
end

---Run action `name` of the handle in the main instance.
---@param name string
---@param args any[]
function M.send(name, args)
  notify(("return require('%s')._action(...)"):format(MAIN), { S.id, name, args or {} })
end

---@param buf integer
---@param keys table<string, Lib.Companion.WireKey>
local function bind(buf, keys)
  for lhs, spec in pairs(keys) do
    local name, prompt = spec.name, spec.prompt
    local args = type(spec.args) == "table" and spec.args or {}
    vim.keymap.set("n", lhs, function()
      if prompt then
        vim.ui.input({ prompt = prompt }, function(text)
          if text ~= nil then
            local with = vim.deepcopy(args)
            with[#with + 1] = text
            M.send(name, with)
          end
        end)
      else
        M.send(name, args)
      end
    end, { buffer = buf, nowait = true, desc = "companion: " .. name })
  end
  if keys.q == nil then
    vim.keymap.set("n", "q", function()
      vim.cmd("qa!")
    end, { buffer = buf, nowait = true, desc = "companion: close" })
  end
end

---@param cfg Lib.Companion.Config
local function setup(cfg)
  local buf = vim.api.nvim_get_current_buf()
  S.buf = buf
  S.ns = vim.api.nvim_create_namespace("lib.nvim.companion")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].undolevels = -1
  pcall(vim.api.nvim_buf_set_name, buf, "companion://" .. cfg.title)
  if cfg.filetype then
    pcall(vim.cmd, "syntax enable")
    vim.bo[buf].filetype = cfg.filetype
  end
  vim.o.title = true
  vim.o.showmode = false
  vim.o.ruler = false
  vim.o.laststatus = 2
  vim.o.statusline = " %{get(g:, 'companion_title', '')}%= q:close "
  vim.wo.wrap = false
  vim.wo.cursorline = true
  vim.wo.number = false
  vim.wo.signcolumn = "no"
  M.set_title(cfg.title)
  bind(buf, cfg.keys or {})
end

---Replace the content, keeping the cursor line where the new content still has it.
---@param payload Lib.Companion.Payload
---@return boolean
function M.render(payload)
  local buf = S.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local lines = payload.lines or {}
  local win = vim.fn.bufwinid(buf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, S.ns, 0, -1)
  for _, h in ipairs(payload.highlights or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, S.ns, h.line, h.col_start, {
      end_col = h.col_end,
      hl_group = h.group,
      strict = false,
    })
  end
  if cursor and win ~= -1 then
    local row = math.min(cursor[1], math.max(#lines, 1))
    pcall(vim.api.nvim_win_set_cursor, win, { row, cursor[2] })
  end
  if payload.title and payload.title ~= S.title then
    M.set_title(payload.title)
  end
  return true
end

---@param title string
---@return boolean
function M.set_title(title)
  S.title = title
  vim.g.companion_title = title
  vim.o.titlestring = title
  if S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    pcall(vim.api.nvim_buf_set_name, S.buf, "companion://" .. title)
  end
  return true
end

---Quit (scheduled: this runs inside the main's notification).
---@return boolean
function M.quit()
  vim.schedule(function()
    vim.cmd("qa!")
  end)
  return true
end

---@param opts { server: string, id: integer }
local function boot(opts)
  local ok, chan = pcall(vim.fn.sockconnect, "pipe", opts.server, { rpc = true })
  if not ok or type(chan) ~= "number" or chan <= 0 then
    return fail("cannot reach the main instance at " .. tostring(opts.server))
  end
  S.main = chan
  S.id = opts.id
  local sok, mine = pcall(vim.fn.serverstart)
  if not sok or type(mine) ~= "string" or mine == "" then
    return fail("cannot start a server: " .. tostring(mine))
  end
  local aok, cfg = call(("return require('%s')._attach(...)"):format(MAIN), { opts.id, mine })
  if not aok or type(cfg) ~= "table" then
    return fail("attach failed: " .. tostring(cfg))
  end
  if cfg.closed then
    vim.cmd("qa!")
    return
  end
  setup(cfg)

  -- On the way out: tell the main. A notification, never a request: the main may be
  -- busy and then send its own quit request to us, and Neovim only serves the channel
  -- it is blocked on, so two requests in flight across the two channels would freeze
  -- both editors for good. Exiting cancels queued writes, so the loop gets FLUSH_MS
  -- to put the notification on the wire; a main that misses it notices the dead
  -- channel by its liveness check within a second.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      if not S.main then
        return
      end
      notify(("return require('%s')._detach(...)"):format(MAIN), { opts.id })
      vim.wait(FLUSH_MS, function()
        return false
      end, 10)
    end,
  })
  -- A main that died takes its channel with it: no orphan companion.
  local timer = vim.uv.new_timer()
  timer:start(LIVENESS_MS, LIVENESS_MS, function()
    vim.schedule(function()
      local info = S.main and vim.api.nvim_get_chan_info(S.main) or {}
      if vim.tbl_isempty(info) then
        timer:stop()
        S.main = nil
        vim.cmd("qa!")
      end
    end)
  end)
end

---Entry point from the companion's `--cmd`. Everything waits for `VimEnter`:
---at `--cmd` time the initial buffer and window do not exist yet.
---@param opts { server: string, id: integer }
function M.start(opts)
  if type(opts) ~= "table" or type(opts.server) ~= "string" or type(opts.id) ~= "number" then
    return fail("start needs { server = <main servername>, id = <handle id> }")
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      boot(opts)
    end,
  })
end

return M
