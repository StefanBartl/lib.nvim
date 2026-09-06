---@module 'lib.nvim.system.rpc_pipe'
---@brief Start a predictable named-pipe RPC server on Windows with neotest compatibility

require("lib.nvim.system.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.system.rpc_pipe]")

local M = {}

--- Try to start a Windows named-pipe RPC server and export NVIM_LISTEN_ADDRESS.
--- No-op on non-Windows platforms and inside detected test environments.
---@param opts? { debug?: boolean, allow_override?: boolean }
--- `debug`: emit vim.notify debug/warn messages (default false).
--- `allow_override`: allow an already-set `NVIM_LISTEN_ADDRESS` to win over the pipe (default true).
---@return nil
function M.setup(opts)
  opts = opts or {}
  local debug = opts.debug or false
  local allow_override = opts.allow_override ~= false

  --- CDX: duplicates Windows detection instead of reusing
  --- `lib.nvim.cross.platform.is_windows`, which the sibling `system.env`
  --- module uses for exactly this so detection logic stays in one place.
  local is_windows = package.config:sub(1, 1) == "\\"
  if not is_windows then
    if debug then
      notify.debug("[system.rpc] skipping: not Windows")
    end
    return
  end

  -- Test environments must not get a real pipe wired in.
  local is_test_env = vim.env.NEOTEST_RUNNING == "1"
    or vim.env.PLENARY_TEST_TIMEOUT ~= nil
    or vim.v.progname:match("nvim%-test")

  if is_test_env and debug then
    notify.debug("[system.rpc] detected test environment, skipping RPC setup")
    return
  end

  -- If NVIM_LISTEN_ADDRESS is already set and override is allowed, respect it
  if allow_override and vim.env.NVIM_LISTEN_ADDRESS then
    if debug then
      notify.debug("[system.rpc] NVIM_LISTEN_ADDRESS already set: " .. vim.env.NVIM_LISTEN_ADDRESS)
    end
    return
  end

  local uname = os.getenv("USERNAME") or "user"
  local pipe = ([[\\.\pipe\nvim-%s]]):format(uname)

  local function dbg(msg)
    if debug then
      notify.debug("[system.rpc] " .. msg)
    end
  end

  local function warn(msg)
    if debug then
      notify.warn("[system.rpc] " .. msg)
    end
  end

  pcall(function()
    if vim.fn.exists("*serverstart") == 1 then
      dbg("attempting serverstart for pipe: " .. pipe)
      local ok = vim.fn.serverstart(pipe)

      if ok == 0 then
        warn("serverstart returned 0 (could not start pipe). Falling back silently.")
        return
      else
        dbg("serverstart succeeded; address: " .. tostring(ok))
      end
    else
      warn("serverstart() not available in this build of Neovim")
    end
  end)

  if not is_test_env then
    vim.env.NVIM_LISTEN_ADDRESS = pipe
    dbg("exported NVIM_LISTEN_ADDRESS=" .. pipe)
  end
end

--- Check if RPC pipe is active
---@return boolean
function M.is_active()
  return vim.env.NVIM_LISTEN_ADDRESS ~= nil
end

--- Get current RPC address
---@return string|nil
function M.get_address()
  return vim.env.NVIM_LISTEN_ADDRESS
end

--- Clear RPC address (useful for tests)
---@return nil
function M.clear()
  vim.env.NVIM_LISTEN_ADDRESS = nil
end

---@type Lib.System.RpcPipe
return M
