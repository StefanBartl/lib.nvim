---@module 'lib.nvim.bindings.keymap.tap'
--- A recording of every keymap that gets set or deleted, whoever sets it.
---@description
--- **The gap.** `registry.conflicts()` only knows what went through lib.nvim's
--- `register`/`set`. A raw `vim.keymap.set`, an `nvim_set_keymap`, a lazy.nvim
--- `keys` entry are invisible to it -- and `nvim_get_keymap()` cannot make up
--- for that, because it reports the *winner* of each key: a mapping that was
--- overwritten is gone without a trace. That is how two bindings on `<M-h>` in
--- the same mode went unnoticed.
---
--- **The tap.** Wraps the four `vim.api` keymap functions and records each call
--- that succeeded, with its mode, key, buffer, `desc` and the file and line it
--- came from. Collisions are then read off the recording: the same key set
--- twice in the same mode and buffer scope with no deletion in between.
---
--- ```lua
--- -- as early as possible, before any plugin binds a key:
--- --   nvim --cmd "lua require('lib.nvim.bindings.keymap.tap').install()"
--- local tap = require("lib.nvim.bindings.keymap.tap")
--- tap.install()
--- -- ... later, once everything has loaded:
--- for _, c in ipairs(tap.collisions()) do
---   print(c.mode, c.lhs, #c.claimants)
--- end
--- ```
---
--- **Only `vim.api` is wrapped.** `vim.keymap.set` and `vim.keymap.del` end in
--- exactly these four calls, so wrapping them as well would count every binding
--- twice -- and the lower level also catches a `vim.keymap.set` a plugin cached
--- in a local before the tap existed. What it cannot catch is a plugin that
--- cached `vim.api.nvim_set_keymap` itself before `install()`, which is why it
--- has to be installed early. Calls made before `install()` are not recorded at
--- all.
---
--- **Not a collision.** A deletion between two bindings of a key is a re-bind.
--- The same call site binding the same thing twice (a `FileType` autocmd
--- firing again, a `:source`) is a re-bind. A buffer-local and a global
--- mapping never meet. And lazy.nvim's own mapping for a `keys` entry,
--- followed by the plugin's mapping with the same description, is a collision
--- in form only: it is reported with `benign = "lazy-stub"` so a caller can
--- filter it. That needs lazy's deletion of its placeholder in between; a
--- placeholder overwritten without one is dead, and stays a real collision.
---
--- **Not seen.** Mappings made with Ex commands (`:nnoremap`, `:nunmap`,
--- `mapset()`), so a Vimscript plugin is invisible and an `:nunmap` between two
--- bindings does not count as the re-bind it is. The recording stops at
--- `M.max_events`; `truncated()` says whether it did.
---
--- Opt-in and never automatic: requiring lib.nvim installs nothing.
---@see lib.nvim.bindings.keymap.registry
---@see lib.nvim.bindings.keymap.runtime

local lhs_mod = require("lib.nvim.bindings.keymap.lhs")

local M = {}

local SELF = debug.getinfo(1, "S").source

--- Chunk name of the wrappers: not an `@file`, on purpose -- see `make_wrapper`.
local WRAPPER = "=lib.nvim.bindings.keymap.tap"

---@type Lib.Keymap.TapEvent[]
local log = {}

---@type { active: boolean, truncated: boolean }
local state = { active = false, truncated = false }

---One switch per installed wrapper layer, read by that layer's wrapper (which lives
---in its own chunk, see `make_wrapper`). A layer that `uninstall()` could not take
---off the API -- a foreign wrapper sits on top of it -- stays in the call chain
---for good, and its switch must stay off when a later `install()` puts a new layer
---on top, or every call would be recorded once per layer.
---@type { active: boolean }[]
local layers = {}

---How many events are kept. A long session binds buffer-local maps on every
---attach (an LSP client alone sets dozens); 18000 events cost about 9 MB. Past
---the limit the recording stops and `truncated()` says so. Set before the
---recording grows; `0` or `math.huge` for no limit.
M.max_events = 50000

---Lua patterns for source paths that are not callers: instrumentation that wraps a function and
---calls it on (a telemetry hook around lib.nvim's `register`) would otherwise be named as the
---place every binding came from. A frame whose file matches one is looked past, like Neovim's own.
---Paths use forward slashes. Empty by default; a config that has such a hook adds its pattern.
---@type string[]
M.skip = {}

---@type table<string, function>|nil
local originals
---@type table<string, function>|nil
local wrappers

local FUNCS = { "nvim_set_keymap", "nvim_buf_set_keymap", "nvim_del_keymap", "nvim_buf_del_keymap" }

--- The chunk name `vim.keymap.set` was compiled under when this module loaded.
--- On a build whose Lua is stripped that is a bare `?`, with nothing to match
--- by name; the function itself still knows. Only trusted when it is not a
--- file path (a plugin that wrapped `vim.keymap.set` before us would otherwise
--- make *its* file count as Neovim's).
---@type string|nil
local KEYMAP_SRC = (function()
  local info = debug.getinfo(vim.keymap.set, "S")
  local src = info and info.source
  if type(src) == "string" and src:sub(1, 1) ~= "@" then
    return src
  end
  return nil
end)()

---@internal
--- Neovim's own `vim/keymap.lua`. Its chunk name depends on the build: a file
--- (`@.../runtime/lua/vim/keymap.lua`) where the runtime is read from disk, a
--- bare `vim/keymap` where it is compiled into the binary.
---@param src string  # `debug.getinfo(...).source`
---@return boolean
local function is_vim_keymap(src)
  if src == KEYMAP_SRC then
    return true
  end
  local name = src:gsub("^[@=]", ""):gsub("\\", "/")
  return name == "vim/keymap" or name == "vim/keymap.lua" or name:find("/vim/keymap%.lua$") ~= nil
end

---@internal
---@param path string|nil  # A source path with forward slashes, nil for a chunk without a file.
---@return boolean
local function skipped(path)
  if not path then
    return false
  end
  for _, pattern in ipairs(M.skip) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

---@internal
--- Where the binding call really came from: the first stack frame that is
--- neither this file, nor Neovim's `vim/keymap.lua`, nor lib.nvim's own keymap
--- wrappers (those only report `via = "lib"`).
---@return string source "file:line", or "?"
---@return Lib.Keymap.Via via
local function origin()
  local via = "raw"
  ---@type { level: integer, source: string, lazy: boolean }[]
  local callers = {}
  local last_lib = 0
  for level = 2, 40 do
    -- A caller after the last lib.nvim frame, and a few frames of nothing from lib.nvim since:
    -- the chain of its own frames is over, no need to walk the rest of the stack.
    if level - last_lib > 8 and callers[#callers] and callers[#callers].level > last_lib then
      break
    end
    local info = debug.getinfo(level, "Sl")
    if not info then
      break
    end
    local src = info.source
    if src ~= SELF and src ~= WRAPPER and src ~= "=[C]" then
      local path = src:sub(1, 1) == "@" and src:sub(2):gsub("\\", "/") or nil
      if is_vim_keymap(src) or skipped(path) then
        -- Neovim's own wrapper, or instrumentation listed in `M.skip`: look further out.
      elseif path and path:find("/lua/lib/nvim/bindings/keymap/[%w_]+%.lua$") then
        via = "lib"
        last_lib = level
      else
        callers[#callers + 1] = {
          level = level,
          source = ("%s:%d"):format(path or info.short_src, info.currentline or -1),
          lazy = path ~= nil and path:find("/lazy/core/handler/keys%.lua$") ~= nil,
        }
      end
    end
  end
  -- Raw binding: the first frame outside Neovim and lib.nvim is the caller. Through lib.nvim the
  -- caller of its public API is wanted, and a wrapper that something put around `vim.keymap.set`
  -- (a telemetry hook) sits *inside* lib's frames and must not pass for it: the first frame after
  -- the last one of lib's.
  for _, c in ipairs(callers) do
    if c.level > last_lib then
      return c.source, (via ~= "lib" and c.lazy) and "lazy" or via
    end
  end
  return "?", via
end

---@internal
--- Whether the recording has reached `max_events` (and remembers that it did).
---@return boolean
local function full()
  local limit = M.max_events
  if type(limit) == "number" and limit > 0 and #log >= limit then
    state.truncated = true
    return true
  end
  return false
end

---@internal
--- Resolve `0`/`true` ("the current buffer") to the real number at the moment
--- of binding, so events compare with `==` later.
---@param buf integer|boolean|nil
---@return integer|nil
local function real_buffer(buf)
  if buf == nil or buf == false then
    return nil
  end
  if buf == true or buf == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return buf
end

---@internal
--- Something comparable about *what* is bound, to tell "the same binding made
--- again" from "another binding": the call site, the description and the
--- target. A function is identified by where it was defined, because a re-fired
--- autocmd creates a new closure for the same definition each time.
---@param rhs any
---@param opts table
---@param src string
---@return string
local function fingerprint(rhs, opts, src)
  local target
  if type(opts.callback) == "function" then
    local info = debug.getinfo(opts.callback, "S")
    target = ("fn:%s:%d"):format(info.short_src, info.linedefined)
  else
    target = "rhs:" .. tostring(rhs)
  end
  return table.concat({ src, tostring(opts.desc or ""), target }, "\0")
end

---@internal
---@param mode string
---@param lhs string
---@param rhs string
---@param opts table|nil
---@param buffer integer|nil
local function on_set(mode, lhs, rhs, opts, buffer)
  if full() then
    return
  end
  opts = type(opts) == "table" and opts or {}
  local src, via = origin()
  local key = lhs_mod.normalize(lhs)
  local kind = type(opts.callback) == "function" and "function"
    or (type(rhs) == "string" and rhs ~= "") and "string"
    or "none"
  for _, m in ipairs(lhs_mod.modes(mode)) do
    log[#log + 1] = {
      op = "set",
      mode = m,
      lhs = lhs,
      key = key,
      buffer = buffer,
      desc = (opts.desc ~= nil and opts.desc ~= "") and opts.desc or nil,
      rhs = kind == "string" and rhs or nil,
      rhs_kind = kind,
      source = src,
      via = via,
      fp = fingerprint(rhs, opts, src),
    }
  end
end

---@internal
---@param mode string
---@param lhs string
---@param buffer integer|nil
local function on_del(mode, lhs, buffer)
  if full() then
    return
  end
  local src, via = origin()
  local key = lhs_mod.normalize(lhs)
  for _, m in ipairs(lhs_mod.modes(mode)) do
    log[#log + 1] = {
      op = "del",
      mode = m,
      lhs = lhs,
      key = key,
      buffer = buffer,
      rhs_kind = "none",
      source = src,
      via = via,
      fp = "del",
    }
  end
end

---@internal
--- What to record for each wrapped function, given the arguments it was called
--- with.
---@type table<string, fun(...: any)>
local HANDLERS = {
  nvim_set_keymap = function(mode, lhs, rhs, opts)
    on_set(mode, lhs, rhs, opts, nil)
  end,
  nvim_buf_set_keymap = function(buf, mode, lhs, rhs, opts)
    on_set(mode, lhs, rhs, opts, real_buffer(buf))
  end,
  nvim_del_keymap = function(mode, lhs)
    on_del(mode, lhs, nil)
  end,
  nvim_buf_del_keymap = function(buf, mode, lhs)
    on_del(mode, lhs, real_buffer(buf))
  end,
}

---@internal
--- Re-raise an error of the original function as the original would have
--- raised it.
---
--- The API functions are C: an error is stamped with the position of the Lua
--- function that called them. Called plainly, that is the wrapper -- a
--- `tap.lua:NN:` the caller never wrote -- and called through `pcall`, as it has
--- to be here, there is no stamp at all. So the stamp of the wrapper's own
--- caller is put back, and the message reads exactly as it did before the tap.
---@param err any
---@param caller table|nil  # `debug.getinfo` of the wrapper's caller.
local function raise(err, caller)
  if type(err) == "string" and caller and (caller.currentline or -1) > 0 then
    err = ("%s:%d: %s"):format(caller.short_src, caller.currentline, err)
  end
  error(err, 0)
end

--- The wrapper's code. Compiled by `make_wrapper` under the chunk name `WRAPPER`.
local WRAPPER_CODE = [[
local orig, handle, state, raise = ...
local pcall, unpack, getinfo, pack_len = pcall, unpack, debug.getinfo, vim.F.pack_len
return function(...)
  local res = pack_len(pcall(orig, ...))
  if not res[1] then
    raise(res[2], getinfo(2, "Sl"))
  end
  if state.active then
    pcall(handle, ...)
  end
  return unpack(res, 2, res.n)
end
]]

---@internal
--- The wrapper for one `vim.api` function. The original runs first, so
--- nothing is recorded for a call that failed and the failure goes to the
--- caller unchanged (see `raise`). Recording is itself `pcall`ed: a bug here
--- must never cost anyone a keymap.
---
--- **Why the wrapper is compiled from a string.** Neovim stamps every Lua
--- mapping with the script and line that set it (`sid`/`lnum`, what `:verbose
--- map` prints), found by walking up the stack to the first frame whose source
--- is an `@file`. A wrapper defined in this file would be that frame, and every
--- mapping set while the tap is installed would claim to come from `tap.lua`.
--- A chunk named `=...` is not an `@file`, so Neovim steps over it to the real
--- caller and the stamp stays truthful.
---@param name string
---@param orig function
---@return function
local function make_wrapper(name, orig)
  local layer = { active = true }
  layers[#layers + 1] = layer
  local chunk = assert(load(WRAPPER_CODE, WRAPPER))
  return chunk(orig, HANDLERS[name], layer, raise)
end

---Start recording. Idempotent.
---
---Call it before the plugins you want to watch bind anything; keymaps set
---earlier are not in the recording (and a plugin that cached
---`vim.api.nvim_set_keymap` before this ran is not seen at all).
---@return boolean installed # `true` when this call installed the tap, `false` when it already was.
function M.install()
  if state.active then
    return false
  end
  originals = originals or {}
  wrappers = wrappers or {}
  for _, name in ipairs(FUNCS) do
    if vim.api[name] ~= wrappers[name] then
      -- Not ours (first install, or a foreign wrapper sits on top of ours
      -- after an `uninstall()` that could not remove it): wrap what is
      -- there now.
      originals[name] = vim.api[name]
      wrappers[name] = make_wrapper(name, vim.api[name])
      vim.api[name] = wrappers[name]
    end
  end
  state.active = true
  return true
end

---Stop recording and put the original functions back.
---
---If something else wrapped them after the tap did, that wrapper is not
---torn out -- the tap's own layer stays as a pass-through, and the call
---returns `false` with the names it could not restore. The recording is kept;
---`clear()` drops it.
---@return boolean restored
---@return string[] left # Function names still wrapped.
function M.uninstall()
  local left = {}
  state.active = false
  -- Every layer goes quiet for good, also the ones that stay in the chain below.
  for _, layer in ipairs(layers) do
    layer.active = false
  end
  layers = {}
  if not originals or not wrappers then
    return true, left
  end
  for _, name in ipairs(FUNCS) do
    if vim.api[name] == wrappers[name] then
      vim.api[name] = originals[name]
      originals[name], wrappers[name] = nil, nil
    elseif wrappers[name] ~= nil then
      left[#left + 1] = name
    end
  end
  return #left == 0, left
end

---Whether the tap is recording right now.
---@return boolean
function M.is_installed()
  return state.active
end

---The recording so far, oldest first. A copy of the list; the events inside
---are shared and meant to be read.
---@return Lib.Keymap.TapEvent[]
function M.log()
  return vim.list_extend({}, log)
end

---Forget the recording (the tap stays installed) and let it grow again if it had
---stopped at `max_events`.
---@return integer removed
function M.clear()
  local n = #log
  log = {}
  state.truncated = false
  return n
end

---Whether the recording stopped at `max_events`: bindings after that point are
---not in it, so a clean `collisions()` is not evidence of anything.
---@return boolean
function M.truncated()
  return state.truncated
end

---@internal
---@param e Lib.Keymap.TapEvent
---@return Lib.Keymap.Registered
local function claimant(e)
  return {
    plugin = e.via == "lazy" and "lazy.nvim" or "(raw)",
    name = e.key,
    lhs = e.lhs,
    mode = e.mode,
    desc = e.desc,
    rhs = e.rhs,
    bound = true,
    direct = true,
    buffer = e.buffer,
    source = e.source,
    via = e.via,
  }
end

---@internal
--- `"lazy-stub"` for lazy.nvim's own mapping followed by the plugin's mapping of
--- the same description (a `plugin: ` prefix in front of either is ignored);
--- nil otherwise.
---
--- lazy.nvim first binds a placeholder for a `keys` entry, **deletes** it before
--- it loads the plugin, binds the real mapping, and the plugin then binds its own.
--- So the benign run is the one that *starts right after a deletion*. A
--- placeholder that something overwrites without lazy having deleted it is not
--- benign -- it is dead, and the plugin it stands for is never lazy-loaded
--- through that key -- however alike the descriptions are.
---@param claimants Lib.Keymap.Registered[]
---@param restarted boolean|nil  # The run began after a deletion of the key.
---@return string|nil
local function benign_kind(claimants, restarted)
  if not restarted or #claimants ~= 2 then
    return nil
  end
  local first, second = claimants[1], claimants[2]
  if first.via ~= "lazy" or not first.desc or not second.desc then
    return nil
  end
  -- `register()` prefixes the description with the plugin name ("files: Open"),
  -- lazy.nvim's placeholder carries the spec's own text ("Open").
  local function bare(desc)
    return (desc:gsub("^[%w%._%-/]+:%s*", ""))
  end
  if bare(first.desc) == bare(second.desc) then
    return "lazy-stub"
  end
  return nil
end

---Collisions in a recording: the same key bound more than once in the same
---mode and buffer scope, with no deletion in between and not by the same call
---site for the same thing.
---
---Pure: it reads `events` (the tap's own recording when omitted) and touches
---nothing else, so it can be exercised on a hand-made list.
---@param events? Lib.Keymap.TapEvent[]
---@return Lib.Keymap.Conflict[]
function M.collisions(events)
  events = events or log
  ---@type table<string, Lib.Keymap.TapEvent[]>
  local runs = {}
  ---@type Lib.Keymap.Conflict[]
  local out = {}

  ---@param key string
  local function flush(key)
    local run = runs[key]
    runs[key] = nil
    if run and #run > 1 then
      local claimants = {}
      for _, e in ipairs(run) do
        claimants[#claimants + 1] = claimant(e)
      end
      out[#out + 1] = {
        mode = run[1].mode,
        lhs = run[1].key,
        claimants = claimants,
        benign = benign_kind(claimants, run.restarted),
      }
    end
  end

  ---Keys whose last event was a deletion: the next run starts after one.
  ---@type table<string, true>
  local deleted = {}

  for _, e in ipairs(events) do
    local key = table.concat({ e.mode, lhs_mod.scope(e.buffer), e.key }, "\0")
    if e.op == "del" then
      flush(key)
      deleted[key] = true
    else
      local run = runs[key]
      if not run then
        run = { restarted = deleted[key] }
        deleted[key] = nil
        runs[key] = run
      end
      for i, prev in ipairs(run) do
        if prev.fp == e.fp then
          table.remove(run, i)
          break
        end
      end
      run[#run + 1] = e
    end
  end
  local pending = vim.tbl_keys(runs)
  for _, key in ipairs(pending) do
    flush(key)
  end

  table.sort(out, function(a, b)
    return (a.lhs .. a.mode) < (b.lhs .. b.mode)
  end)
  return out
end

-- A reload (`package.loaded` cleared and the module required again, as a dev reload does) would
-- leave the old copy's wrappers on the API next to the new copy's: two taps recording every call,
-- and an `uninstall()` of the new one that restores nothing. The copies find each other through a
-- global: the new one takes over the recording and the settings, silences the old one and, if the
-- old one was recording, goes on recording itself.
local HANDOVER = "__lib_nvim_keymap_tap"
local prior = rawget(_G, HANDOVER)
rawset(_G, HANDOVER, M)
if type(prior) == "table" and prior ~= M and type(prior.uninstall) == "function" then
  local was_active = type(prior.is_installed) == "function" and prior.is_installed()
  local events = type(prior.log) == "function" and prior.log() or {}
  if type(prior.max_events) == "number" then
    M.max_events = prior.max_events
  end
  if type(prior.skip) == "table" then
    M.skip = prior.skip
  end
  pcall(prior.uninstall)
  for _, e in ipairs(events) do
    log[#log + 1] = e
  end
  if was_active then
    M.install()
  end
end

return M
