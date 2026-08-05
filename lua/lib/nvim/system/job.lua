---@module 'lib.nvim.system.job'
--- Thin wrapper around `vim.system` that restores plenary.job's line-buffered,
--- schedule-safe callback ergonomics (`on_stdout(err, line)` / `on_stderr(err,
--- line)`, invoked once per output line, already on the main loop) without
--- pulling in plenary.nvim as a dependency.
---
---   require("lib.nvim.system.job").start({
---     command = "head",
---     args = { "-n", "50", file },
---     on_stdout = function(_, line) ... end,
---     on_stderr = function(_, line) ... end,
---   })

require("lib.nvim.system.@types")

local M = {}

---@internal
---@param cb fun(err: nil, line: string)|nil
---@return fun(err: string|nil, data: string|nil)|nil
local function line_buffered(cb)
  if not cb then
    return nil
  end

  local pending = ""
  return function(_, data)
    if not data then
      -- EOF. A trailing fragment with no newline after it is still a line,
      -- and plenty of real output ends that way — a file whose last line has
      -- no terminator, `printf` without a trailing \n, a program killed
      -- mid-line. Returning here without flushing drops it silently, so the
      -- last line of a preview would just be missing.
      if pending ~= "" then
        local last = pending:gsub("\r$", "")
        pending = ""
        vim.schedule(function()
          cb(nil, last)
        end)
      end
      return
    end
    pending = pending .. data
    while true do
      local nl = pending:find("\n", 1, true)
      if not nl then
        break
      end
      local line = pending:sub(1, nl - 1):gsub("\r$", "")
      pending = pending:sub(nl + 1)
      vim.schedule(function()
        cb(nil, line)
      end)
    end
  end
end

--- Start a command, streaming stdout/stderr to the given callbacks one line
--- at a time (each call already wrapped in `vim.schedule`).
---@param opts Lib.System.Job.Opts
---@return vim.SystemObj
function M.start(opts)
  local cmd = { opts.command }
  for _, arg in ipairs(opts.args or {}) do
    table.insert(cmd, arg)
  end

  return vim.system(cmd, {
    stdout = line_buffered(opts.on_stdout),
    stderr = line_buffered(opts.on_stderr),
  })
end

---@type Lib.System.Job
return M
