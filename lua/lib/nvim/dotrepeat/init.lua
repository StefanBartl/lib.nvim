---@module 'lib.nvim.dotrepeat'
--- Wire native Vim `.`-repeat through the `operatorfunc` mechanism, without
--- depending on `vim-repeat` or any other plugin.
---
--- Vim's dot-repeat re-invokes whatever `operatorfunc` currently names, not
--- the mapping that first triggered it. `M.run(fn)` stores `fn` as the
--- module-local "pending" callback, points `operatorfunc` at one stable
--- dispatcher (`M._invoke`, reached from Vimscript via `v:lua`), and fires
--- the operator machinery once with a single-character pseudo-motion
--- (`g@l`). Because the dispatcher always re-reads the module-local pending
--- fn, pressing `.` later re-invokes `M._invoke`, which calls whatever was
--- stored on the *previous* `M.run` — i.e. the same `fn` — again.
---
--- Usage:
--- ```lua
--- local dotrepeat = require("lib.nvim.dotrepeat")
---
--- local function insert_snippet()
---   vim.api.nvim_put({ "-- snippet" }, "l", true, true)
--- end
---
--- vim.keymap.set("n", "<leader>x", function()
---   dotrepeat.run(insert_snippet)
--- end)
--- -- <leader>x inserts once; pressing `.` afterwards inserts it again.
--- ```

require("lib.nvim.dotrepeat.@types")

local M = {}

---@type Lib.Dotrepeat.Fn|nil
local pending_fn = nil

---Dispatcher installed as `operatorfunc`. Reached from Vimscript via
---`v:lua.require'lib.nvim.dotrepeat'._invoke` — must stay a stable,
---always-the-same reference so `operatorfunc` keeps naming it across
---`.`-repeats.
---@param motion_type string|nil
function M._invoke(motion_type)
  local fn = pending_fn
  if fn then
    fn(motion_type)
  end
end

---Wrap `fn` so it becomes repeatable via `M.run`. `fn` matches Vim's
---`operatorfunc` contract: zero-arg or taking the motion-type string.
---@param fn Lib.Dotrepeat.Fn
---@return Lib.Dotrepeat.Fn wrapped Calling this is equivalent to `M.run(fn)`
function M.repeatable(fn)
  return function(motion_type)
    M.run(function()
      fn(motion_type)
    end)
  end
end

---Entry point: run `fn` once now, and set things up so pressing `.`
---afterwards runs it again.
---@param fn Lib.Dotrepeat.Fn
function M.run(fn)
  pending_fn = fn
  vim.o.operatorfunc = "v:lua.require'lib.nvim.dotrepeat'._invoke"
  vim.cmd("normal! g@l")
end

return M
