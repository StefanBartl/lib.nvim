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
--- at once) is returned without suspending; a component that cannot open at all counts as
--- cancelled, so the coroutine never waits for an answer that cannot come. An error in the
--- coroutine is reported with its traceback, not swallowed. The caller's own callbacks
--- (`on_submit`, `on_cancel`, `on_select`, `on_answer`) still run, before the coroutine resumes; an
--- error in one of them is raised after the answer has been delivered, never instead of it.
---
--- `kit.confirm` is single-instance: opening one answers the dialog it replaces as cancelled, which
--- resumes that dialog's coroutine. When several coroutines may ask at overlapping moments (a timer,
--- an event handler), use `kit.async.ask`: it waits its turn behind whatever dialog is open.

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

  local started, start_err = pcall(start, deliver)
  if settled then
    -- Answered already (while opening, or a callback raised after delivering): the answer wins,
    -- the error is reported.
    if not started then
      report(co, start_err)
    end
    return vim.F.unpack_len(result)
  end
  if not started then
    error(start_err, 0)
  end
  suspended = true
  return co_yield()
end

--- A callback for a component: the caller's own `user` callback first (an error in it is raised
--- afterwards), then `deliver`, so that no error can cost the coroutine its answer. When arguments
--- follow `deliver` they are what is delivered (their count counts, `nil`s included); otherwise
--- it is whatever the callback itself receives.
---@param user function|nil
---@param deliver fun(...)
---@param ... any
---@return fun(...)
local function chain(user, deliver, ...)
  local fixed = vim.F.pack_len(...)
  return function(...)
    local ok, err = true, nil
    if user then
      ok, err = pcall(user, ...)
    end
    if fixed.n > 0 then
      deliver(vim.F.unpack_len(fixed))
    else
      deliver(...)
    end
    if not ok then
      error(err, 0)
    end
  end
end

--- Open `kit.confirm` and wait for the answer: `true`/`false`, or the label (`nil` when dismissed)
--- for a `choices` list. Single-instance, see the header; `ask` is the call for overlapping flows.
---@param opts table  # as `kit.confirm`
---@return boolean|string|nil
function M.confirm(opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    o.on_answer = chain(o.on_answer, deliver)
    require("lib.nvim.ui.kit.confirm").open(o)
  end)
end

--- Open `kit.ask` (waits its turn behind open dialogs, always answers) and wait for the answer. A
--- question dropped because `abandoned()` turned true answers `nil`.
---@param opts table  # as `kit.ask`
---@return boolean|string|nil
function M.ask(opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    o.on_answer = chain(o.on_answer, deliver)
    local user_abandoned = o.abandoned
    if user_abandoned then
      o.abandoned = function()
        local dropped = user_abandoned()
        if dropped then
          deliver(nil)
        end
        return dropped
      end
    end
    require("lib.nvim.ui.kit.confirm").ask(o)
  end)
end

--- Open an `on_submit`/`on_cancel`-shaped component (`kit.input`, `kit.form`, `kit.live_input`, ...)
--- and wait for it. Returns the submitted value, or `nil` and `true` when it was cancelled -- also
--- when the component could not open at all (it returns nothing and calls neither callback).
---@param open_fn fun(opts: table): any
---@param opts table
---@return any value
---@return boolean? cancelled
function M.submit(open_fn, opts)
  return M.await(function(deliver)
    local o = vim.tbl_extend("force", {}, opts or {})
    local user_submit = o.on_submit
    o.on_submit = function(value)
      chain(user_submit, deliver, value, false)(value)
    end
    o.on_cancel = chain(o.on_cancel, deliver, nil, true)
    if open_fn(o) == nil then
      deliver(nil, true)
    end
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
    local user_select = o.on_select
    o.on_select = function(item, idx)
      chain(user_select, deliver, item, idx)(item, idx)
    end
    o.on_cancel = chain(o.on_cancel, deliver, nil, nil)
    require("lib.nvim.ui.kit.select").open(o)
  end)
end

return M
