---@module 'lib.nvim.system.rpc_pipe'
---@brief Start a predictable named-pipe RPC server on Windows

require("lib.nvim.system.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.system.rpc_pipe]")

local M = {}

--- Address of the pipe this module started (or found pre-set), nil until `setup` got that far.
---@type string|nil
local address = nil

--- True while `vim.env.NVIM_LISTEN_ADDRESS` holds a value this module wrote.
---@type boolean
local exported = false

--- Whether the server behind `address` was started by this module (so `clear` may stop it).
---@type boolean
local started = false

--- Start a Windows named-pipe RPC server on a predictable name, so external tools can reach this
--- Neovim without knowing its pid. No-op on non-Windows platforms and inside detected test
--- environments.
---
--- The address is NOT exported to the environment by default: every child process would inherit
--- `NVIM_LISTEN_ADDRESS`, and a child `nvim` (`:terminal nvim`, `GIT_EDITOR=nvim`, a headless test
--- run, a plugin job) honours it at startup, tries to bind the very pipe its parent holds and dies
--- with "address already in use". Consumers connect by the pipe NAME, which `get_address()` returns.
---@param opts? { debug?: boolean, allow_override?: boolean, export?: boolean, pipe?: string }
--- `debug`: emit vim.notify debug/warn messages (default false).
--- `allow_override`: an already-set `NVIM_LISTEN_ADDRESS` wins over the pipe (default true).
--- `export`: also write the address to `vim.env.NVIM_LISTEN_ADDRESS` (default false, see above).
--- `pipe`: pipe name to use instead of `\\.\pipe\nvim-<USERNAME>`.
---@return nil
function M.setup(opts)
  opts = opts or {}
  local debug = opts.debug or false
  local allow_override = opts.allow_override ~= false
  local export = opts.export == true

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

  --- CDX: duplicates Windows detection instead of reusing
  --- `lib.nvim.cross.platform.is_windows`, which the sibling `system.env`
  --- module uses for exactly this so detection logic stays in one place.
  local is_windows = package.config:sub(1, 1) == "\\"
  if not is_windows then
    dbg("skipping: not Windows")
    return
  end

  -- Test environments must not get a real pipe wired in.
  local is_test_env = vim.env.NEOTEST_RUNNING == "1"
    or vim.env.PLENARY_TEST_TIMEOUT ~= nil
    or vim.v.progname:match("nvim%-test")
  if is_test_env then
    dbg("detected test environment, skipping RPC setup")
    return
  end

  -- Already set up: a second serverstart on the same name only fails.
  if address then
    dbg("already set up: " .. address)
    return
  end

  -- A pre-set NVIM_LISTEN_ADDRESS means Neovim itself started the server there.
  local preset = vim.env.NVIM_LISTEN_ADDRESS
  if allow_override and preset and preset ~= "" then
    address = preset
    dbg("NVIM_LISTEN_ADDRESS already set: " .. address)
    return
  end

  local pipe = opts.pipe or ([[\\.\pipe\nvim-%s]]):format(os.getenv("USERNAME") or "user")

  local ok, result = pcall(vim.fn.serverstart, pipe)
  if not ok or result == 0 or result == "" then
    warn(
      "serverstart failed for " .. pipe .. " (" .. tostring(result) .. "). Falling back silently."
    )
    return
  end
  address = pipe
  started = true
  dbg("serverstart succeeded; address: " .. tostring(result))

  if export then
    vim.env.NVIM_LISTEN_ADDRESS = pipe
    exported = true
    dbg("exported NVIM_LISTEN_ADDRESS=" .. pipe)
  end
end

--- Is a predictable RPC pipe available (started by `setup`, or pre-set in the environment)?
---@return boolean
function M.is_active()
  return address ~= nil
end

--- Get the RPC address (the pipe name to connect to).
---@return string|nil
function M.get_address()
  return address
end

--- Forget the address, unset an exported `NVIM_LISTEN_ADDRESS` and stop the pipe if `setup`
--- started it (useful in tests).
---@return nil
function M.clear()
  if started and address then
    pcall(vim.fn.serverstop, address)
  end
  if exported then
    vim.env.NVIM_LISTEN_ADDRESS = nil
  end
  address, exported, started = nil, false, false
end

---@type Lib.System.RpcPipe
return M
