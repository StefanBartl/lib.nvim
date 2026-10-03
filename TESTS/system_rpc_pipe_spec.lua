-- TESTS/system_rpc_pipe_spec.lua -- lib.nvim.system.rpc_pipe
--
-- The point of the module is a predictable pipe NAME. What it must not do is leak the address into
-- the environment of every child: a child nvim honours NVIM_LISTEN_ADDRESS at startup, tries to bind
-- the pipe its parent holds and exits 1 ("address already in use"). The Windows cases start real
-- pipes (unique names, never the user's) and run real child nvims.

return function(H)
  local eq, ok = H.eq, H.ok
  local MODULE = "lib.nvim.system.rpc_pipe"
  local is_windows = package.config:sub(1, 1) == "\\"

  -- The module keeps its state per load: every case starts from a fresh copy.
  local function fresh()
    package.loaded[MODULE] = nil
    return require(MODULE)
  end

  local counter = 0
  local function unique_pipe()
    counter = counter + 1
    return ([[\\.\pipe\libnvim-rpc-spec-%d-%d]]):format(vim.fn.getpid(), counter)
  end

  local function listed(address)
    for _, a in ipairs(vim.fn.serverlist()) do
      if a == address then
        return true
      end
    end
    return false
  end

  --- Exit code of a plain child nvim that inherits this process's environment.
  --- `vim.fn.system` on purpose: `vim.system` without an `env` does not pick up later `vim.env`
  --- writes (measured), so it would hide the very inheritance this spec is about.
  local function child_exit()
    local out = vim.fn.system({ vim.v.progpath, "--headless", "--clean", "-c", "qa!" })
    return vim.v.shell_error, out
  end

  local saved = {
    listen = vim.env.NVIM_LISTEN_ADDRESS,
    neotest = vim.env.NEOTEST_RUNNING,
  }
  vim.env.NVIM_LISTEN_ADDRESS = nil
  vim.env.NEOTEST_RUNNING = nil

  if not is_windows then
    local rpc = fresh()
    rpc.setup({ pipe = unique_pipe() })
    eq(rpc.is_active(), false, "rpc_pipe: no-op off Windows (inactive)")
    eq(rpc.get_address(), nil, "rpc_pipe: no-op off Windows (no address)")
    vim.env.NVIM_LISTEN_ADDRESS = saved.listen
    vim.env.NEOTEST_RUNNING = saved.neotest
    return
  end

  -- default: pipe started, NOT exported, children unaffected --------------------
  local rpc = fresh()
  local pipe = unique_pipe()
  eq(rpc.is_active(), false, "rpc_pipe: inactive before setup")
  rpc.setup({ pipe = pipe })
  eq(rpc.is_active(), true, "rpc_pipe: active after setup")
  eq(rpc.get_address(), pipe, "rpc_pipe: get_address is the pipe name")
  ok(listed(pipe), "rpc_pipe: the pipe is a server of this nvim")
  eq(
    vim.env.NVIM_LISTEN_ADDRESS,
    nil,
    "rpc_pipe: default setup does not export NVIM_LISTEN_ADDRESS"
  )
  local code, err = child_exit()
  eq(code, 0, "rpc_pipe: a child nvim starts normally (stderr: " .. err .. ")")

  -- idempotent: a second setup keeps the first pipe -------------------------------
  rpc.setup({ pipe = unique_pipe() })
  eq(rpc.get_address(), pipe, "rpc_pipe: a second setup keeps the first address")

  rpc.clear()
  eq(rpc.is_active(), false, "rpc_pipe: clear forgets the address")
  eq(listed(pipe), false, "rpc_pipe: clear stops the pipe setup started")

  -- export = true is still possible, and still hazardous for children ---------------
  rpc = fresh()
  pipe = unique_pipe()
  rpc.setup({ pipe = pipe, export = true })
  eq(vim.env.NVIM_LISTEN_ADDRESS, pipe, "rpc_pipe: export = true writes NVIM_LISTEN_ADDRESS")
  code = child_exit()
  ok(code ~= 0, "rpc_pipe: an exported address makes a child nvim fail (the reason it is opt-in)")
  rpc.clear()
  eq(vim.env.NVIM_LISTEN_ADDRESS, nil, "rpc_pipe: clear unsets what setup exported")
  code = child_exit()
  eq(code, 0, "rpc_pipe: children start again after clear")

  -- a pre-set variable wins unless allow_override = false ----------------------------
  rpc = fresh()
  vim.env.NVIM_LISTEN_ADDRESS = "preset-address"
  rpc.setup({ pipe = unique_pipe() })
  eq(
    rpc.get_address(),
    "preset-address",
    "rpc_pipe: a pre-set NVIM_LISTEN_ADDRESS is reported, not replaced"
  )
  rpc.clear()
  eq(
    vim.env.NVIM_LISTEN_ADDRESS,
    "preset-address",
    "rpc_pipe: clear leaves a variable it did not write"
  )
  vim.env.NVIM_LISTEN_ADDRESS = nil

  rpc = fresh()
  vim.env.NVIM_LISTEN_ADDRESS = "preset-address"
  pipe = unique_pipe()
  rpc.setup({ pipe = pipe, allow_override = false })
  eq(rpc.get_address(), pipe, "rpc_pipe: allow_override = false starts its own pipe")
  rpc.clear()
  vim.env.NVIM_LISTEN_ADDRESS = nil

  -- test environments get no pipe ----------------------------------------------------
  rpc = fresh()
  vim.env.NEOTEST_RUNNING = "1"
  rpc.setup({ pipe = unique_pipe() })
  eq(rpc.is_active(), false, "rpc_pipe: a detected test environment skips setup")
  vim.env.NEOTEST_RUNNING = nil

  vim.env.NVIM_LISTEN_ADDRESS = saved.listen
  vim.env.NEOTEST_RUNNING = saved.neotest
end
