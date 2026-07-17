---@module 'lib.nvim.system'
--- Host-environment namespace: OS/shell/path snapshot plus the Windows RPC-pipe
--- helper. This is the library-side home of what used to live in a per-config
--- `system` module.
---
---   local system = require("lib.nvim.system")
---   local env = system.env.get()          -- computed snapshot (memoized)
---   system.info.show()                    -- system-info float + clipboard
---   system.proc_trace.start()             -- log slow system()/jobstart calls
---   system.setup({ publish_globals = true }) -- opt-in vim.g.* + more
---
--- Direct requiring stays tree-shake friendly:
---   local env = require("lib.nvim.system.env").get()

require("lib.nvim.system.@types")

---@type Lib.System
---@diagnostic disable-next-line: missing-fields
local M = {}

M.env = require("lib.nvim.system.env")
M.rpc_pipe = require("lib.nvim.system.rpc_pipe")
M.info = require("lib.nvim.system.info")
M.proc_trace = require("lib.nvim.system.proc_trace")

--- Opt-in activation of environment "features".
--- Everything is off by default so the module stays a pure helper; a config
--- turns on exactly what it wants.
---@param opts? Lib.System.SetupOptions
---@return Lib.System.Env # The (now cached) environment snapshot.
function M.setup(opts)
  opts = opts or {}

  local pg = opts.publish_globals
  if pg then
    M.env.publish_globals(type(pg) == "table" and pg or nil)
  end

  local rpc = opts.rpc_pipe
  if rpc then
    M.rpc_pipe.setup(type(rpc) == "table" and rpc or nil)
  end

  local uc = opts.info_usercmd
  if uc then
    M.info.create_usercmd(type(uc) == "string" and uc or nil)
  end

  return M.env.get()
end

return M
