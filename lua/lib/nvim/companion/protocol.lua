---@module 'lib.nvim.companion.protocol'
--- The protocol layer of a companion window: handle registry, the messages a
--- companion receives, attach / action / detach dispatch.
---
--- Knows nothing about processes or terminals. A registry talks to companions
--- through a `Lib.Companion.Transport` (`connect`, `notify`, `alive`, `close`);
--- `lib.nvim.companion` passes the msgpack-RPC one, the specs a fake that
--- records every message. Every call into a channel is guarded: a dead
--- companion ends as a detach (handle closed, `on_close` once), never as an
--- error in the caller.
---
--- Nothing here ever BLOCKS on a companion: every message is a notification.
--- The main and a companion hold one channel in each direction, and Neovim
--- only serves the channel it is blocked on, so a request from the main while
--- the companion is blocked in its own request to the main (its `_detach` on
--- the way out) would freeze both editors for good. The transport has no
--- `request` for that reason.

local M = {}

local CLIENT = "lib.nvim.companion.client"

---How long a companion may take to report in before its handle is closed
---(a terminal that never ran the inner `nvim` would otherwise leave the handle
---pending forever, with no signal to the caller).
M.ATTACH_TIMEOUT_MS = 15000

-- ── messages ─────────────────────────────────────────────────────────────────

M.messages = {}

---@param payload Lib.Companion.Payload
---@return Lib.Companion.Message
function M.messages.render(payload)
  return { code = ("return require('%s').render(...)"):format(CLIENT), args = { payload } }
end

---@param title string
---@return Lib.Companion.Message
function M.messages.set_title(title)
  return { code = ("return require('%s').set_title(...)"):format(CLIENT), args = { title } }
end

---@return Lib.Companion.Message
function M.messages.quit()
  return { code = ("return require('%s').quit()"):format(CLIENT), args = {} }
end

-- ── validation ───────────────────────────────────────────────────────────────

---@param lines any
---@return string[]|nil
---@return string|nil err
local function check_lines(lines)
  if lines == nil then
    return {}
  end
  if type(lines) ~= "table" then
    return nil, "lines must be a list of strings"
  end
  for i, l in ipairs(lines) do
    if type(l) ~= "string" then
      return nil, ("line %d is not a string"):format(i)
    end
    if l:find("\n", 1, true) then
      return nil, ("line %d holds a newline"):format(i)
    end
  end
  return lines
end

---@param hls any
---@return Lib.Companion.Highlight[]|nil
---@return string|nil err
local function check_highlights(hls)
  if hls == nil then
    return {}
  end
  if type(hls) ~= "table" then
    return nil, "highlights must be a list"
  end
  for i, h in ipairs(hls) do
    if
      type(h) ~= "table"
      or type(h.line) ~= "number"
      or type(h.col_start) ~= "number"
      or type(h.col_end) ~= "number"
      or type(h.group) ~= "string"
    then
      return nil, ("highlight %d needs line, col_start, col_end and group"):format(i)
    end
  end
  return hls
end

---@param keys any
---@param actions table<string, function>
---@return table<string, Lib.Companion.KeySpec>|nil
---@return string|nil err
local function check_keys(keys, actions)
  if keys == nil then
    return {}
  end
  if type(keys) ~= "table" then
    return nil, "keys must be a table"
  end
  for lhs, spec in pairs(keys) do
    if type(lhs) ~= "string" or lhs == "" then
      return nil, "a key lhs must be a non-empty string"
    end
    local name
    if type(spec) == "string" then
      name = spec
    elseif type(spec) == "table" and type(spec[1]) == "string" then
      name = spec[1]
      if spec.prompt ~= nil and type(spec.prompt) ~= "string" then
        return nil, ("key %s: prompt must be a string"):format(lhs)
      end
    else
      return nil, ("key %s: expected an action name or { name, args... }"):format(lhs)
    end
    if type(actions[name]) ~= "function" then
      return nil, ("key %s: no action %q"):format(lhs, name)
    end
  end
  return keys
end

-- ── handle ───────────────────────────────────────────────────────────────────

---@class Lib.Companion.ProtocolHandle : Lib.Companion.Handle
---@field title string
---@field lines string[]
---@field highlights Lib.Companion.Highlight[]
---@field filetype string|nil
---@field actions table<string, function>
---@field keys table<string, Lib.Companion.KeySpec>
---@field on_close fun()|nil
---@field state "pending"|"attaching"|"attached"|"closed"
---@field servername string|nil # the companion's server, known from attach on
---@field chan integer|nil # the channel to the companion's server
---@field stop fun()|nil # ends the companion process when it is ours (direct spawn)
---@field opened_at integer # registry clock (ms) at create
---@field attach_timeout integer|false # ms until a companion that never attached is closed
---@field registry Lib.Companion.Registry
local Handle = {}
Handle.__index = Handle

---@return Lib.Companion.Payload
function Handle:payload()
  return { lines = self.lines, highlights = self.highlights, title = self.title }
end

---@return boolean
function Handle:is_open()
  return self.state ~= "closed"
end

---@return boolean
function Handle:is_attached()
  return self.state == "attached"
end

---Send `msg` to an attached companion; a failed send means the companion is
---gone and ends in a detach. Nothing is sent before the companion attached
---(the content waits in the handle and goes with the first render).
---@param msg Lib.Companion.Message
---@return boolean sent
function Handle:send(msg)
  if self.state ~= "attached" or not self.chan then
    return false
  end
  local ok = self.registry.transport.notify(self.chan, msg)
  if not ok then
    self.registry:detach(self.id)
    return false
  end
  return true
end

---Replace the content. Returns `false` once closed or for invalid input; the
---companion keeps its cursor line where the new content still has it.
---@param lines string[]
---@param highlights? Lib.Companion.Highlight[]
---@return boolean
---@return string|nil err
function Handle:update(lines, highlights)
  if self.state == "closed" then
    return false, "closed"
  end
  local ls, err = check_lines(lines)
  if not ls then
    return false, err
  end
  local hls, herr = check_highlights(highlights)
  if not hls then
    return false, herr
  end
  self.lines, self.highlights = ls, hls
  self:send(M.messages.render(self:payload()))
  return true
end

---@param title string
---@return boolean
function Handle:set_title(title)
  if self.state == "closed" or type(title) ~= "string" then
    return false
  end
  self.title = title
  self:send(M.messages.set_title(title))
  return true
end

---Close the companion: ask it to quit (when it is reachable), drop the channel,
---end the process when it is ours, forget the handle, call `on_close` once.
---
---The quit is a notification, never a request (see the module header). A
---companion that has reported in but whose channel back is not open yet
---(state `attaching`: the scheduled `connect` has not run) is connected here
---first, so it is told as well instead of staying open until the main exits.
function Handle:close()
  if self.state == "closed" then
    return
  end
  local t = self.registry.transport
  if not self.chan and self.state == "attaching" and self.servername then
    local chan = t.connect(self.servername)
    if chan then
      self.chan = chan
    end
  end
  if self.chan then
    pcall(t.notify, self.chan, M.messages.quit())
    pcall(t.close, self.chan)
    self.chan = nil
  end
  if self.stop then
    pcall(self.stop)
  end
  self.registry:finish(self.id)
end

-- ── registry ─────────────────────────────────────────────────────────────────

---@class Lib.Companion.Registry
---@field transport Lib.Companion.Transport
---@field clock fun(): integer # milliseconds, monotonic (`vim.uv.now`)
---@field handles table<integer, Lib.Companion.ProtocolHandle>
---@field next_id integer
local Registry = {}
Registry.__index = Registry

---@param transport Lib.Companion.Transport
---@param clock? fun(): integer # the attach-timeout clock in ms (default `vim.uv.now`)
---@return Lib.Companion.Registry
function M.new(transport, clock)
  return setmetatable({
    transport = transport,
    clock = clock or function()
      return vim.uv.now()
    end,
    handles = {},
    next_id = 1,
  }, Registry)
end

---A new handle in state `pending` (no companion yet). Validates `opts`.
---@param opts Lib.Companion.OpenOpts
---@return Lib.Companion.ProtocolHandle|nil
---@return string|nil err
function Registry:create(opts)
  opts = opts or {}
  if opts.title ~= nil and type(opts.title) ~= "string" then
    return nil, "title must be a string"
  end
  local attach_timeout = opts.attach_timeout
  if attach_timeout == nil then
    attach_timeout = M.ATTACH_TIMEOUT_MS
  elseif attach_timeout ~= false and (type(attach_timeout) ~= "number" or attach_timeout <= 0) then
    return nil, "attach_timeout must be a positive number of milliseconds or false"
  end
  local lines, err = check_lines(opts.lines)
  if not lines then
    return nil, err
  end
  local hls, herr = check_highlights(opts.highlights)
  if not hls then
    return nil, herr
  end
  local actions = opts.actions or {}
  if type(actions) ~= "table" then
    return nil, "actions must be a table of functions"
  end
  for name, fn in pairs(actions) do
    if type(name) ~= "string" or type(fn) ~= "function" then
      return nil, "actions must map names to functions"
    end
  end
  local keys, kerr = check_keys(opts.keys, actions)
  if not keys then
    return nil, kerr
  end
  if opts.on_close ~= nil and type(opts.on_close) ~= "function" then
    return nil, "on_close must be a function"
  end
  local id = self.next_id
  self.next_id = id + 1
  local h = setmetatable({
    id = id,
    title = opts.title or "Companion",
    lines = lines,
    highlights = hls,
    filetype = opts.filetype,
    actions = actions,
    keys = keys,
    on_close = opts.on_close,
    state = "pending",
    opened_at = self.clock(),
    attach_timeout = attach_timeout,
    registry = self,
  }, Handle)
  self.handles[id] = h
  return h
end

---@param id integer
---@return Lib.Companion.ProtocolHandle|nil
function Registry:get(id)
  return self.handles[id]
end

---@return integer
function Registry:count()
  local n = 0
  for _ in pairs(self.handles) do
    n = n + 1
  end
  return n
end

---The companion `id` reports in with its own server name. Returns what it has
---to show and bind; `{ closed = true }` tells a companion whose handle is
---already gone to quit. The channel back is opened by `connect`, not here: the
---companion is blocked in this very request.
---@param id integer
---@param servername string
---@return Lib.Companion.Config
function Registry:attach(id, servername)
  local h = self.handles[id]
  if not h or h.state == "closed" or type(servername) ~= "string" or servername == "" then
    return { closed = true, title = "", keys = {} }
  end
  h.servername = servername
  h.state = "attaching"
  return { title = h.title, filetype = h.filetype, keys = M.wire_keys(h.keys) }
end

---The keys as they travel to the companion: `{ name, args, prompt }` per lhs.
---A spec like `{ "jump", prompt = "..." }` is a Lua table with an array AND a
---hash part, which msgpack cannot carry ("Cannot convert given Lua table").
---@param keys table<string, Lib.Companion.KeySpec>
---@return table<string, Lib.Companion.WireKey>
function M.wire_keys(keys)
  local out = {}
  for lhs, spec in pairs(keys) do
    if type(spec) == "string" then
      out[lhs] = { name = spec, args = {} }
    else
      local args = {}
      for i = 2, #spec do
        args[#args + 1] = spec[i]
      end
      out[lhs] = { name = spec[1], args = args, prompt = spec.prompt }
    end
  end
  return out
end

---Open the channel to the companion that attached and push the content. A
---companion that cannot be reached counts as gone (detach).
---@param id integer
---@return boolean connected
function Registry:connect(id)
  local h = self.handles[id]
  if not h or h.state ~= "attaching" or not h.servername then
    return false
  end
  local chan = self.transport.connect(h.servername)
  if not chan then
    self:detach(id)
    return false
  end
  h.chan = chan
  h.state = "attached"
  h:send(M.messages.render(h:payload()))
  return h.state == "attached"
end

---A key in the companion: run action `name` of handle `id` in this instance.
---@param id integer
---@param name string
---@param args any[]|nil
---@return boolean ok
---@return string|nil err
function Registry:action(id, name, args)
  local h = self.handles[id]
  if not h or h.state == "closed" then
    return false, ("no companion %s"):format(tostring(id))
  end
  local fn = h.actions[name]
  if type(fn) ~= "function" then
    return false, ("companion %d: no action %q"):format(id, tostring(name))
  end
  args = type(args) == "table" and args or {}
  local ok, err = pcall(fn, unpack(args, 1, args.n or #args))
  if not ok then
    return false, ("companion %d: action %q failed: %s"):format(id, name, tostring(err))
  end
  return true
end

---The companion is gone (it said so, its process ended, or its channel died):
---drop the channel, close the handle, `on_close` once. Idempotent.
---@param id integer
function Registry:detach(id)
  local h = self.handles[id]
  if not h then
    return
  end
  if h.chan then
    pcall(self.transport.close, h.chan)
    h.chan = nil
  end
  self:finish(id)
end

---Forget handle `id` without telling anyone (a spawn that failed).
---@param id integer
function Registry:drop(id)
  local h = self.handles[id]
  if h then
    h.state = "closed"
    self.handles[id] = nil
  end
end

---Mark `id` closed, forget it and call its `on_close` (once, errors reported,
---never raised).
---@param id integer
function Registry:finish(id)
  local h = self.handles[id]
  if not h or h.state == "closed" then
    return
  end
  h.state = "closed"
  self.handles[id] = nil
  if h.on_close then
    local ok, err = pcall(h.on_close)
    if not ok then
      vim.notify(
        ("companion %d: on_close failed: %s"):format(id, tostring(err)),
        vim.log.levels.ERROR
      )
    end
  end
end

---The liveness check: detach every attached companion whose channel is gone (a
---crashed or killed process) and close every handle whose companion has not
---attached within its `attach_timeout` (a terminal that never ran the inner
---`nvim`: the process is ended when it is ours, `on_close` runs, a warning
---says so). Returns how many handles ended.
---@return integer
function Registry:check()
  local gone, late = {}, {}
  local now = self.clock()
  for id, h in pairs(self.handles) do
    if h.state == "attached" then
      if h.chan and not self.transport.alive(h.chan) then
        gone[#gone + 1] = id
      end
    elseif h.attach_timeout and now - h.opened_at >= h.attach_timeout then
      late[#late + 1] = id
    end
  end
  for _, id in ipairs(gone) do
    self:detach(id)
  end
  for _, id in ipairs(late) do
    local h = self.handles[id]
    vim.notify(
      ("companion %d (%s): no companion attached within %d ms, closed"):format(
        id,
        h.title,
        h.attach_timeout
      ),
      vim.log.levels.WARN
    )
    h:close()
  end
  return #gone + #late
end

---Close every handle (the main instance is leaving).
function Registry:close_all()
  local ids = {}
  for id in pairs(self.handles) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local h = self.handles[id]
    if h then
      h:close()
    end
  end
end

return M
