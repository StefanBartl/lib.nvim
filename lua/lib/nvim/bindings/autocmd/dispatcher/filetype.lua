---@module 'lib.nvim.bindings.autocmd.dispatcher.filetype'
--- `FileType`-keyed convenience over `lib.nvim.bindings.autocmd.dispatcher`: keys on
--- `ev.match` (the matched filetype) and defaults `context` to a
--- `lib.nvim.buffer.context` snapshot of the triggering buffer, so a handler
--- gets `ctx.context.filetype`/`ctx.context:is_normal()`/... for free without
--- every caller wiring that up by hand.

local M = {}

---@param opts? { group?: string, context?: fun(ev: Lib.Autocmd.Args): any }
---@return Lib.Autocmd.Dispatcher.Handle
function M.new(opts)
  opts = opts or {}

  -- `lib.nvim.bindings.autocmd.dispatcher` eagerly pulls this file in (`M.filetype =
  -- ...`), so requiring it back at module top level would be a load-time
  -- cycle -- deferred to first actual use instead.
  local dispatcher = require("lib.nvim.bindings.autocmd.dispatcher")

  return dispatcher.new({
    event = "FileType",
    group = opts.group,
    key = function(ev)
      return ev.match
    end,
    context = opts.context or function(ev)
      return require("lib.nvim.buffer.context").get(ev.buf)
    end,
  })
end

---@type Lib.Autocmd.Dispatcher.FileType
return M
