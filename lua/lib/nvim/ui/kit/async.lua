---@module 'lib.nvim.ui.kit.async'
--- Linear code over kit's callback components, without blocking Neovim.
---
--- `kit.sync` waits with `vim.wait()`, and Neovim does not run typed keys while it waits: the
--- dialog never sees them and the call returns after its timeout (ten minutes by default). A
--- coroutine does not have that problem: `kit.async.run` starts one, a call such as
--- `kit.async.input` opens the dialog and suspends the coroutine, and the dialog's callback resumes
--- it with the answer while the editor stays responsive.
---
---   kit.async.run(function()
---     local name = kit.async.input({ prompt = "Name" })        -- nil when cancelled
---     if not name then return end
---     if not kit.async.confirm({ question = ("Create %s?"):format(name) }) then return end
---     create(name)
---   end)
---
--- Every `kit.async.*` function must be called inside `run`: outside one there is nothing to
--- suspend (and a coroutine of another scheduler must not be resumed from here), which is an
--- error naming `run`. The result of a dismissed dialog is the same
--- value the callback form gives: `false`/`nil` from a confirm, `nil` from input, select, form.
---
--- A dialog that answers while it is being opened (a stub, a float that could not open and fell back
--- at once) is returned without suspending. An error in the coroutine is reported with its
--- traceback, not swallowed.

local M = {}

local co_running = coroutine.running

--- The coroutines `run` started. Only those may be suspended here: another scheduler's coroutine
--- (a test runner's, an async framework's) would be resumed by this module behind its back.
---@type table<thread, true>
local owned = setmetatable({}, { __mode = "k" })
local co_yield = coroutine.yield
local co_resume = coroutine.resume

--- Report an error raised inside a coroutine started by `run`, with the coroutine's traceback.
---@param co thread
---@param err any
local function report(co, err)
  local trace = debug.traceback(co, tostring(err), 0)
  vim.schedule(function()
    vim.notify("lib.nvim.ui.kit.async: " .. trace, vim.log.levels.ERROR)
  end)
end

--- Resume `co` with `...`; an error is reported, never raised into the dialog's callback.
---@param co thread
---@param ... any
local function resume(co, ...)
  local ok, err = co_resume(co, ...)
  if not ok then
    report(co, err)
  end
end

--- Start `fn` in a coroutine and run it until its first suspension. Returns the coroutine.
---@param fn fun(...)
---@param ... any  # passed to `fn`
---@return thread
function M.run(fn, ...)
  local co = coroutine.create(fn)
  owned[co] = true
  resume(co, ...)
  return co
end

--- Suspend the calling coroutine until `start` hands it a result.
---
--- `start(deliver)` opens a component and arranges for `deliver(...)` to be called when it answers
--- (once; later calls are ignored). `await` returns whatever `deliver` was given.
---@param start fun(deliver: fun(...))
---@return ...
function M.await(start)
  local co, is_main = co_running()
  if is_main or not owned[co] then
    error("lib.nvim.ui.kit.async: call this inside kit.async.run(function() ... end)", 3)
  end

  local settled, suspended = false, false
  local result ---@type table
  local function deliver(...)
    if settled then
      return
    end
    settled = true
    result = vim.F.pack_len(...)
    if suspended then
      resume(co, vim.F.unpack_len(result))
    end
  end

  start(deliver)
  if settled then
    return vim.F.unpack_len(result)
  end
  suspended = true
  return co_yield()
end

--- Open `kit.confirm` and wait for the answer: `true`/`false`, or the label (`nil` when dismissed)
--- for a `choices` list.
---@param opts table  # as `kit.confirm`
---@return boolean|string|nil
function M.confirm(opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    o.on_answer = deliver
    require("lib.nvim.ui.kit.confirm").open(o)
  end)
end

--- Open `kit.ask` (waits its turn behind open dialogs, always answers) and wait for the answer.
---@param opts table  # as `kit.ask`
---@return boolean|string|nil
function M.ask(opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    o.on_answer = deliver
    require("lib.nvim.ui.kit.confirm").ask(o)
  end)
end

--- Open an `on_submit`/`on_cancel`-shaped component (`kit.input`, `kit.form`, `kit.live_input`, ...)
--- and wait for it. Returns the submitted value, or `nil` and `true` when it was cancelled.
---@param open_fn fun(opts: table): any
---@param opts table
---@return any value
---@return boolean? cancelled
function M.submit(open_fn, opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    local user_submit, user_cancel = o.on_submit, o.on_cancel
    o.on_submit = function(value)
      if user_submit then
        user_submit(value)
      end
      deliver(value, false)
    end
    o.on_cancel = function()
      if user_cancel then
        user_cancel()
      end
      deliver(nil, true)
    end
    open_fn(o)
  end)
end

--- `kit.input`: the typed line, or `nil` and `true` when cancelled.
---@param opts table
---@return string|nil line
---@return boolean? cancelled
function M.input(opts)
  return M.submit(require("lib.nvim.ui.kit.input").open, opts)
end

--- `kit.form`: the table of field values, or `nil` and `true` when cancelled.
---@param opts table
---@return table|nil values
---@return boolean? cancelled
function M.form(opts)
  return M.submit(require("lib.nvim.ui.kit.form").open, opts)
end

--- `kit.select`: the chosen item and its index, or `nil` when dismissed or there was nothing to pick.
---@param opts table  # as `kit.select`; `on_select`/`on_cancel` are called as well
---@return any item
---@return integer? index
function M.select(opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    local user_select, user_cancel = o.on_select, o.on_cancel
    o.on_select = function(item, idx)
      if user_select then
        user_select(item, idx)
      end
      deliver(item, idx)
    end
    o.on_cancel = function()
      if user_cancel then
        user_cancel()
      end
      deliver(nil, nil)
    end
    require("lib.nvim.ui.kit.select").open(o)
  end)
end

return M
