---@module 'lib.nvim.ui.kit.sync'
--- Bridge one of kit's async, callback-based components (`input`/`form`/
--- `live_input` — anything using the `on_submit`/`on_cancel` contract) back
--- to a plain synchronous return value, via `vim.wait()`. See
--- docs/ROADMAP/UI-KIT-CONCEPT.md §13a for the design rationale and caveats.
---
--- Not a generic wrapper over every kit component: `confirm` and `select`
--- have different callback shapes (`on_answer`, and a silent close with no
--- callback at all on Esc/q respectively) that this does not attempt to
--- normalize — only components using `on_submit`/`on_cancel` are supported.
---
--- Only safe to call from a normal call stack (a command handler, keymap
--- callback, ...) — never from a fast-event/libuv callback context, the same
--- restriction `vim.wait()` itself has.

local M = {}

--- Safety net only, not the expected path: every kit float already closes
--- deterministically via `q`/`<Esc>`/focus-loss, so `done` should flip long
--- before this fires. Guards against an unforeseen bug hanging Neovim.
local DEFAULT_TIMEOUT_MS = 10 * 60 * 1000

--- Open an `on_submit`/`on_cancel`-shaped kit component and block until it
--- resolves, returning its result as a plain value instead of via callback.
---@generic T
---@param open_fn fun(opts: table): any  # e.g. kit.form, kit.input, kit.live_input
---@param opts table                      # forwarded as-is; on_submit/on_cancel are wrapped, not replaced
---@param timeout_ms? integer             # default 10 minutes
---@return T|nil result
---@return boolean cancelled
---@return boolean timed_out
function M.open(open_fn, opts, timeout_ms)
  if vim.in_fast_event() then
    error("lib.nvim.ui.kit.sync: cannot be called from a fast event context (vim.in_fast_event())", 2)
  end

  opts = vim.tbl_extend("force", {}, opts or {})
  timeout_ms = timeout_ms or DEFAULT_TIMEOUT_MS

  local done, cancelled, result = false, false, nil
  local user_on_submit = opts.on_submit
  local user_on_cancel = opts.on_cancel

  opts.on_submit = function(value)
    result = value
    done = true
    if user_on_submit then
      user_on_submit(value)
    end
  end
  opts.on_cancel = function()
    cancelled = true
    done = true
    if user_on_cancel then
      user_on_cancel()
    end
  end

  open_fn(opts)

  -- 10ms interval: `done` flips synchronously inside a keymap-dispatched
  -- callback, so a short interval keeps the return-to-caller lag imperceptible
  -- rather than waiting out vim.wait's (much coarser) default poll interval.
  local ok = vim.wait(timeout_ms, function()
    return done
  end, 10)

  if not ok then
    return nil, false, true
  end
  return result, cancelled, false
end

return M
