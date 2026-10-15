---@module 'lib.nvim.hooks'
--- Hook registry for a pipeline with named stages (`before_apply`, `after_write`, ...): callbacks run in a
--- defined order, a `before_*` hook can veto the step, and a throwing hook never stops the others or the
--- pipeline.
---
--- Extracted from `replacer.nvim`'s `hooks.lua`; the consumers are any plugin with an apply pipeline
--- (`migrate.nvim`, `pdfport.nvim`). Each plugin makes its own registry with `new`, so two plugins never
--- share hooks.
---
--- Order: hooks given to `run` (the plugin's `config.hooks`) first, then the registered ones by ascending
--- `priority` (default 0), equal priorities in registration order.
---
--- Veto: a hook of a vetoable event that returns exactly `false` vetoes. All hooks still run (a later hook
--- may be a cleanup that has to see the event), `run` then returns `proceed = false`. Pass
--- `short_circuit = true` to stop at the first veto instead. A veto of a non-vetoable event is ignored.

local M = {}

---@alias Lib.Hooks.Fn fun(ctx: any): boolean|nil

---@class Lib.Hooks.Opts
---@field events string[]                       Every event name of the registry; any other name is an error.
---@field vetoable? string[]                    Events whose hooks can veto (default: the ones named `before_*`).
---@field short_circuit? boolean                Stop running a vetoable event's hooks at the first veto (default false).
---@field on_error? fun(event: string, err: any, fn: function)  Called for a throwing hook (default: `vim.notify` WARN).

---@class Lib.Hooks.Registry
---@field on fun(event: string, fn: Lib.Hooks.Fn, opts?: { priority?: integer }): fun()  # returns the unregister function
---@field off fun(event: string, fn: Lib.Hooks.Fn): boolean  # whether a hook was removed
---@field clear fun(event?: string)
---@field count fun(event: string): integer
---@field run fun(event: string, ctx?: any, extra?: Lib.Hooks.Fn|Lib.Hooks.Fn[]): boolean, integer  # proceed, number of throwing hooks

---@param name string
---@param kind string
local function bad(name, kind)
  error(("lib.nvim.hooks: unknown event '%s' (%s)"):format(tostring(name), kind), 3)
end

---@param opts Lib.Hooks.Opts
---@return Lib.Hooks.Registry
function M.new(opts)
  if type(opts) ~= "table" or type(opts.events) ~= "table" or #opts.events == 0 then
    error("lib.nvim.hooks.new: opts.events must be a non-empty list of event names", 2)
  end

  local known, vetoable, list = {}, {}, {}
  for _, name in ipairs(opts.events) do
    if type(name) ~= "string" or name == "" then
      error("lib.nvim.hooks.new: event names must be non-empty strings", 2)
    end
    known[name] = true
    list[name] = {}
    vetoable[name] = name:sub(1, 7) == "before_"
  end
  if opts.vetoable then
    for name in pairs(vetoable) do
      vetoable[name] = false
    end
    for _, name in ipairs(opts.vetoable) do
      if not known[name] then
        error(
          ("lib.nvim.hooks.new: vetoable event '%s' is not in events"):format(tostring(name)),
          2
        )
      end
      vetoable[name] = true
    end
  end

  local on_error = opts.on_error
    or function(event, err)
      vim.notify(("hook '%s' errored: %s"):format(event, tostring(err)), vim.log.levels.WARN)
    end

  local seq = 0
  ---@diagnostic disable-next-line: missing-fields
  ---@type Lib.Hooks.Registry
  local reg = {}

  function reg.on(event, fn, hook_opts)
    if not known[event] then
      bad(event, "register")
    end
    if type(fn) ~= "function" then
      error("lib.nvim.hooks: a hook must be a function", 2)
    end
    seq = seq + 1
    local entry = { fn = fn, priority = (hook_opts and hook_opts.priority) or 0, seq = seq }
    local entries = list[event]
    entries[#entries + 1] = entry
    -- Stable by construction: `seq` breaks priority ties.
    table.sort(entries, function(a, b)
      if a.priority ~= b.priority then
        return a.priority < b.priority
      end
      return a.seq < b.seq
    end)
    return function()
      for i, e in ipairs(list[event]) do
        if e == entry then
          table.remove(list[event], i)
          return
        end
      end
    end
  end

  function reg.off(event, fn)
    if not known[event] then
      bad(event, "unregister")
    end
    for i, e in ipairs(list[event]) do
      if e.fn == fn then
        table.remove(list[event], i)
        return true
      end
    end
    return false
  end

  function reg.clear(event)
    if event == nil then
      for name in pairs(list) do
        list[name] = {}
      end
      return
    end
    if not known[event] then
      bad(event, "clear")
    end
    list[event] = {}
  end

  function reg.count(event)
    if not known[event] then
      bad(event, "count")
    end
    return #list[event]
  end

  function reg.run(event, ctx, extra)
    if not known[event] then
      bad(event, "run")
    end
    local fns = {}
    if type(extra) == "function" then
      fns[1] = extra
    elseif type(extra) == "table" then
      for _, fn in ipairs(extra) do
        if type(fn) == "function" then
          fns[#fns + 1] = fn
        end
      end
    end
    -- A snapshot: a hook that registers or removes hooks does not change this run.
    for _, e in ipairs(list[event]) do
      fns[#fns + 1] = e.fn
    end

    local proceed, errors = true, 0
    for _, fn in ipairs(fns) do
      local ok, result = pcall(fn, ctx)
      if not ok then
        errors = errors + 1
        -- The error handler itself must not break the run either.
        pcall(on_error, event, result, fn)
      elseif result == false and vetoable[event] then
        proceed = false
        if opts.short_circuit then
          break
        end
      end
    end
    return proceed, errors
  end

  return reg
end

return M
