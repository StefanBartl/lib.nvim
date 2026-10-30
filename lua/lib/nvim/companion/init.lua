---@module 'lib.nvim.companion'
--- A companion window: a SECOND Neovim in its own terminal window that shows a
--- read-only buffer this instance fills, and whose keys run actions here.
---
--- Logic and state stay in the main instance; the companion is display and
--- input only. The companion connects to this instance over msgpack-RPC
--- (`sockconnect` to `v:servername`), reports in with its own server name
--- (`_attach`), and this instance connects back and pushes the content. Keys
--- pressed there arrive as `_action`; a companion that leaves says so
--- (`_detach`), one that was killed is noticed by a liveness check. On
--- `VimLeavePre` every open companion is told to quit.
---
--- This file is the process / transport layer: the RPC transport, the
--- terminal window (`launch`), the job, the liveness timer. The handle
--- registry and the messages live in `protocol` and are tested with a fake
--- transport. First consumer: the dap.nvim memory view.

local launch = require("lib.nvim.companion.launch")
local protocol = require("lib.nvim.companion.protocol")

local M = {}

local LIVENESS_MS = 1000
-- On `VimLeavePre` the quit notifications are still in the channels' write
-- queues; exiting closes the handles and cancels queued writes, so the loop
-- gets this long to put them on the wire (a companion that misses it quits by
-- its own liveness check within a second).
local FLUSH_MS = 100

-- ── transport: msgpack-RPC over the companion's server ───────────────────────

---@type Lib.Companion.Transport
local transport = {
  connect = function(servername)
    local ok, chan = pcall(vim.fn.sockconnect, "pipe", servername, { rpc = true })
    if not ok or type(chan) ~= "number" or chan <= 0 then
      return nil, "cannot connect to " .. servername .. ": " .. tostring(chan)
    end
    return chan
  end,
  -- Notifications only, never `rpcrequest`: see the protocol module header.
  notify = function(chan, msg)
    local ok = pcall(vim.rpcnotify, chan, "nvim_exec_lua", msg.code, msg.args)
    return ok
  end,
  alive = function(chan)
    local ok, info = pcall(vim.api.nvim_get_chan_info, chan)
    return ok and type(info) == "table" and not vim.tbl_isempty(info)
  end,
  close = function(chan)
    pcall(vim.fn.chanclose, chan)
  end,
}

local registry = protocol.new(transport)

-- ── liveness ─────────────────────────────────────────────────────────────────

local timer

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function ensure_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(LIVENESS_MS, LIVENESS_MS, function()
    vim.schedule(function()
      registry:check()
      if registry:count() == 0 then
        stop_timer()
      end
    end)
  end)
end

-- ── environment ──────────────────────────────────────────────────────────────

---The lib.nvim root (the directory holding `lua/`), from this file's path.
---@return string
local function lib_root()
  local src = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  return (src:gsub("/lua/lib/nvim/companion/init%.lua$", ""))
end

---@return string|nil servername
---@return string|nil err
local function ensure_server()
  local name = vim.v.servername
  if type(name) == "string" and name ~= "" then
    return name
  end
  local ok, started = pcall(vim.fn.serverstart)
  if not ok or type(started) ~= "string" or started == "" then
    return nil, "cannot start an RPC server: " .. tostring(started)
  end
  return started
end

---Is `name` runnable? `vim.fn.executable()` says 0 for a Windows App Execution
---Alias (`wt.exe` of a Store / winget Windows Terminal is one: a 0-byte reparse
---point under `%LOCALAPPDATA%\Microsoft\WindowsApps`), although `CreateProcess`
---runs it. Those are checked by `fs_access(X)` on the alias path.
---@param name string
---@param windows boolean
---@return boolean
function M.is_runnable(name, windows)
  if vim.fn.executable(name) == 1 then
    return true
  end
  if not windows or name:find("[/\\]") then
    return false
  end
  local apps = vim.env.LOCALAPPDATA
  if not apps or apps == "" then
    return false
  end
  local alias = apps:gsub("\\", "/") .. "/Microsoft/WindowsApps/" .. name
  if not alias:lower():find("%.exe$") then
    alias = alias .. ".exe"
  end
  return vim.uv.fs_access(alias, "X") == true
end

---@return Lib.Companion.LaunchEnv
local function launch_env()
  local os_name
  if require("lib.nvim.cross.platform.is_windows")() then
    os_name = "windows"
  elseif require("lib.nvim.cross.platform.is_macos")() then
    os_name = "macos"
  else
    os_name = "linux"
  end
  return {
    os = os_name,
    executable = function(name)
      return M.is_runnable(name, os_name == "windows")
    end,
    TERMINAL = vim.env.TERMINAL,
  }
end

-- ── public API ───────────────────────────────────────────────────────────────

---Open a companion window. Returns the handle, or `nil` and why (nothing is
---left behind then: no handle, no process).
---
---`opts.terminal` is an argv template around the inner `nvim` (`{cmd}`), by
---default the platform's terminal (see `launch.default_terminal`); `false`
---starts a headless companion directly (specs, scripts). A companion that has
---not reported in after `opts.attach_timeout` ms (default
---`protocol.ATTACH_TIMEOUT_MS`, `false` = wait forever) is closed with a
---warning and `on_close`. Content, keys and actions: see the README.
---@param opts Lib.Companion.OpenOpts
---@return Lib.Companion.Handle|nil handle
---@return string|nil err
function M.open(opts)
  opts = opts or {}
  if opts.terminal ~= nil and opts.terminal ~= false and type(opts.terminal) ~= "table" then
    return nil, "terminal must be an argv template or false"
  end
  local server, serr = ensure_server()
  if not server then
    return nil, serr
  end
  local handle, cerr = registry:create(opts)
  if not handle then
    return nil, cerr
  end

  local direct = opts.terminal == false
  local inner = {
    progpath = vim.v.progpath,
    root = lib_root(),
    server = server,
    id = handle.id,
    headless = direct,
  }
  local argv, aerr
  if direct then
    argv, aerr = launch.inner_argv(inner)
  else
    argv, aerr = launch.argv(inner, opts.terminal, opts.env or launch_env(), handle.title)
  end
  if not argv then
    registry:drop(handle.id)
    return nil, aerr
  end

  -- `vim.system`, not `jobstart`: jobstart refuses a program `executable()` does not
  -- know, and that is every Windows App Execution Alias (`wt.exe`); `vim.system`
  -- goes straight to `uv.spawn`, which runs it.
  local on_exit
  if direct then
    -- The process IS the companion: its end is the companion's end.
    local id = handle.id
    on_exit = function()
      vim.schedule(function()
        registry:detach(id)
      end)
    end
  end
  local ok, proc = pcall(vim.system, argv, { detach = not direct, stdin = false }, on_exit)
  if not ok or type(proc) ~= "table" then
    registry:drop(handle.id)
    return nil, ("failed to start %s: %s"):format(argv[1], tostring(proc))
  end
  if direct then
    handle.stop = function()
      pcall(proc.kill, proc, 9)
    end
  end
  ensure_timer()
  return handle
end

---Every open handle, by id.
---@return Lib.Companion.Handle[]
function M.handles()
  local out = {}
  for _, h in pairs(registry.handles) do
    out[#out + 1] = h
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

---Close every companion.
function M.close_all()
  registry:close_all()
end

---The registry (specs and scripts).
---@return Lib.Companion.Registry
function M.registry()
  return registry
end

-- ── called by the companion over RPC ─────────────────────────────────────────

---A companion reports in. Answers right away (the companion waits for it) and
---connects back afterwards.
---@param id integer
---@param servername string
---@return Lib.Companion.Config
function M._attach(id, servername)
  local cfg = registry:attach(id, servername)
  if not cfg.closed then
    vim.schedule(function()
      registry:connect(id)
    end)
  end
  return cfg
end

---A key in the companion. Errors are reported here, never sent back.
---@param id integer
---@param name string
---@param args any[]|nil
---@return boolean
function M._action(id, name, args)
  local ok, err = registry:action(id, name, args)
  if not ok then
    vim.notify(err or "companion action failed", vim.log.levels.WARN)
  end
  return ok
end

---A companion is leaving.
---@param id integer
---@return boolean
function M._detach(id)
  registry:detach(id)
  return true
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("lib.nvim.companion", { clear = true }),
  callback = function()
    local had = registry:count() > 0
    registry:close_all()
    stop_timer()
    if had then
      vim.wait(FLUSH_MS, function()
        return false
      end, 10)
    end
  end,
})

return M
