---@module 'lib.nvim.ui.dialog'
--- The one way a plugin asks the user something: a yes/no, a choice of a few buttons, a line of text.
---
--- Every plugin used to carry its own wrapper around `ui.kit.confirm` with its own fallback when
--- ui.nvim is missing (`vim.ui.select`, `vim.fn.confirm`, nothing at all). This module is that
--- wrapper, once. The backend is the first that loads:
---
---   1. `ui.kit` (ui.nvim)           -- the user's themed kit, presets included
---   2. `lib.nvim.ui.kit`            -- the copy that ships with lib.nvim; looks the same
---   3. native                       -- `vim.ui.select` / `vim.ui.input` (a float that cannot open
---                                      lands here too)
---
--- Contract, whichever backend answers:
---   - the callback runs exactly once, and never before the call has returned (an answer given
---     while the dialog is being opened is delivered on the next loop turn);
---   - a dismissed dialog answers `false` (yes/no), `nil` (choices, text) or index `0` (`choose`).
---
---   local dialog = require("lib.nvim.ui.dialog")
---   dialog.confirm({ question = "Delete init.lua?", on_answer = function(yes) ... end })
---   dialog.choose("Save changes?", "&Save\n&Discard\n&Cancel", 1, function(i) ... end)
---   dialog.input({ prompt = "Name" }, function(name) ... end)   -- nil when cancelled
---
--- `confirm` shows at once and replaces an open confirm (answering it as cancelled). `ask` waits
--- behind whatever dialog is open and is the call for questions raised at a moment the user did not
--- pick (a stream that ends later): see `ui.kit.ask`.

require("lib.nvim.ui.dialog.@types")

local M = {}

--- The kit that answers, and its name; `nil, "native"` when none loads.
---@return table|nil kit
---@return Lib.UI.Dialog.Backend name
local function resolve()
  for _, name in ipairs({ "ui.kit", "lib.nvim.ui.kit" }) do
    local ok, kit = pcall(require, name)
    if ok and type(kit) == "table" and type(kit.confirm) == "function" then
      return kit, name
    end
  end
  return nil, "native"
end

--- The backend that would answer right now.
---@return Lib.UI.Dialog.Backend
function M.backend()
  local _, name = resolve()
  return name
end

--- A callback that runs at most once and not before `settle()` has been called. An answer that
--- comes in while the dialog is still being opened waits for the next loop turn.
---@param cb function|nil
---@return fun(...) answer
---@return fun() settle  # call once the open call has returned
---@return fun() discard  # forget an answer given while opening (the float turned out not to open)
local function once(cb)
  local opening, done, pending = true, false, nil
  local function fire(...)
    if done then
      return
    end
    done = true
    if cb then
      cb(...)
    end
  end
  local function answer(...)
    if opening then
      pending = pending or vim.F.pack_len(...)
    else
      fire(...)
    end
  end
  local function settle()
    opening = false
    if pending then
      local args = pending
      pending = nil
      vim.schedule(function()
        fire(vim.F.unpack_len(args))
      end)
    end
  end
  local function discard()
    pending = nil
  end
  return answer, settle, discard
end

---@param t table|nil
---@return table
local function copy(t)
  return vim.tbl_extend("force", {}, t or {})
end

--- Button labels of `choices` as the kit shows them: a list as it is, a `vim.fn.confirm` string
--- split at newlines, `&` before a hotkey dropped, `&&` a literal `&`, empty pieces skipped.
---@param choices string|string[]|nil
---@return string[]|nil
local function labels_of(choices)
  if type(choices) == "table" then
    return #choices > 0 and choices or nil
  end
  if type(choices) ~= "string" or choices == "" then
    return nil
  end
  local labels = {}
  for piece in vim.gsplit(choices, "\n", { plain = true }) do
    if piece ~= "" then
      local out, marked, i = {}, false, 1
      while i <= #piece do
        local c = piece:sub(i, i)
        if c == "&" and piece:sub(i + 1, i + 1) == "&" then
          out[#out + 1] = "&"
          i = i + 2
        elseif c == "&" and not marked and i < #piece then
          marked = true
          i = i + 1
        else
          out[#out + 1] = c
          i = i + 1
        end
      end
      labels[#labels + 1] = table.concat(out)
    end
  end
  return #labels > 0 and labels or nil
end

--- Ask through `vim.ui.select` (which cannot preselect a default).
---@param opts table
---@param answer fun(...)
local function native_confirm(opts, answer)
  local labels = labels_of(opts.choices)
  local custom = labels ~= nil
  local items = labels or { "Yes", "No" }
  vim.ui.select(
    items,
    { prompt = tostring(opts.question or opts.title or "") },
    function(choice, idx)
      if custom then
        answer(choice)
      else
        answer(idx == 1)
      end
    end
  )
end

--- Show a question and call `opts.on_answer(answer)` once. The options are those of `kit.confirm`
--- (`question`, `choices`, `default`, `kind`, `legend`, `title`, `theme`, `keep_on_focus_lost`).
--- The answer is `true`/`false`, or with `choices` the chosen label (`nil` when dismissed).
---@param opts Lib.UI.Dialog.ConfirmOpts
---@return Lib.UI.Dialog.Backend backend  # which backend took the question
function M.confirm(opts)
  opts = opts or {}
  local kit, name = resolve()
  local answer, settle, discard = once(opts.on_answer)

  if kit then
    local o = copy(opts)
    o.on_answer = answer
    local ok, surf = pcall(kit.confirm, o)
    if ok and surf ~= nil then
      settle()
      return name
    end
    -- The float did not open (the kit has answered "no" on its own by now): ask natively instead.
    discard()
  end

  native_confirm(opts, answer)
  settle()
  return "native"
end

--- Like `confirm`, for a question raised at a moment the user did not pick: it waits behind the
--- dialog that is open instead of replacing it, and a question that stays unanswered for
--- `max_wait_ms` is answered "no". Options as `kit.ask`.
---@param opts Lib.UI.Dialog.ConfirmOpts
---@return Lib.UI.Dialog.Backend backend
function M.ask(opts)
  opts = opts or {}
  local kit, name = resolve()
  local answer, settle = once(opts.on_answer)
  if kit and type(kit.ask) == "function" then
    local o = copy(opts)
    o.on_answer = answer
    if pcall(kit.ask, o) then
      settle()
      return name
    end
  end
  native_confirm(opts, answer)
  settle()
  return "native"
end

--- Map `vim.fn.confirm`'s fifth argument to a kit `kind`.
local KIND_OF_TYPE = { Error = "danger", Warning = "warn", Info = "info" }

--- `vim.fn.confirm` as a callback: `cb(index)` with the 1-based number of the chosen button, `0`
--- when dismissed. `choices` is the `vim.fn.confirm` string (`"&Yes\n&No"`) or a list of labels;
--- `default` the button that starts focused (0 or nil: the first); `msg_type` is `Error`, `Warning`,
--- `Info`, `Question` or `Generic` and only colours the border.
---@param msg string
---@param choices string|string[]
---@param default? integer
---@param cb fun(index: integer)
---@param msg_type? string
---@return Lib.UI.Dialog.Backend backend
function M.choose(msg, choices, default, cb, msg_type)
  local labels = labels_of(choices) or {}
  return M.confirm({
    question = msg,
    choices = choices,
    default = (default and default > 0) and default or 1,
    kind = KIND_OF_TYPE[msg_type or ""],
    on_answer = function(label)
      local index = 0
      for i, l in ipairs(labels) do
        if l == label then
          index = i
          break
        end
      end
      cb(index)
    end,
  })
end

--- Ask for a line of text. `cb(value)` is called once with the text, or `nil` when cancelled, the
--- way `vim.ui.input` does; without `cb`, `opts.on_submit` / `opts.on_cancel` are called as in
--- `kit.input`. Options as `kit.input` (`prompt`, `default`, `completion`, `secret`, ...).
---@param opts Lib.UI.Dialog.InputOpts
---@param cb? fun(value: string|nil)
---@return Lib.UI.Dialog.Backend backend
function M.input(opts, cb)
  opts = opts or {}
  local function deliver(value)
    if cb then
      cb(value)
    elseif value ~= nil then
      if opts.on_submit then
        opts.on_submit(value)
      end
    elseif opts.on_cancel then
      opts.on_cancel()
    end
  end
  local answer, settle, discard = once(deliver)
  local kit, name = resolve()

  if kit and type(kit.input) == "function" then
    local o = copy(opts)
    o.on_submit = function(value)
      answer(value)
    end
    o.on_cancel = function()
      answer(nil)
    end
    local ok, surf = pcall(kit.input, o)
    if ok and surf ~= nil then
      settle()
      return name
    end
    discard()
  end

  if opts.secret then
    -- vim.ui.input has no masking: the prompt of the command line does.
    local ok, text = pcall(vim.fn.inputsecret, tostring(opts.prompt or opts.title or ""))
    answer(ok and text ~= "" and text or nil)
  else
    vim.ui.input({
      prompt = opts.prompt or opts.title,
      default = opts.default,
      completion = opts.completion,
    }, answer)
  end
  settle()
  return "native"
end

return M
