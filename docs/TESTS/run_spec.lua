-- docs/TESTS/run_spec.lua — lib.nvim.cross.run

return function(H)
  local eq, ok = H.eq, H.ok

  local run = require("lib.nvim.cross.run")
  local env = require("lib.nvim.cross.run.env")
  local is_windows = require("lib.nvim.cross.platform.is_windows")()

  -- ---------------------------------------------------------------- shell()

  local is_wsl = require("lib.nvim.cross.platform.is_wsl")()
  local sh = run.shell()
  ok(type(sh.prog) == "string" and sh.prog ~= "", "shell: returns a usable prog")
  eq(
    sh.is_powershell,
    is_windows and not is_wsl,
    "shell: is_powershell matches native-Windows (non-WSL) detection"
  )

  -- --------------------------------------------------------- run_blocking()

  local res = run.run_blocking("echo hello-run-blocking")
  eq(res.code, 0, "run_blocking: a successful command exits 0")
  ok(res.stdout:find("hello-run-blocking", 1, true) ~= nil, "run_blocking: stdout is captured")

  -- ------------------------------------------------- env enrichment, default on

  -- The command must actually see the completed PATH, not just whatever it
  -- would have inherited anyway — prove it by asking the subprocess to print
  -- its own PATH and checking a directory this module's candidate_dirs()
  -- reports for this platform, but which the *current* vim.env.PATH may or
  -- may not already contain.
  -- shell() only ever returns PowerShell (native, non-WSL Windows) or `sh`
  -- (WSL/Linux/macOS) — never cmd.exe — so env-var interpolation syntax
  -- follows that same split, not is_windows() alone.
  local uses_powershell = is_windows and not is_wsl
  local function echo_var(name)
    return uses_powershell and ("echo $env:" .. name) or ("echo $" .. name)
  end

  local dirs = env.candidate_dirs()
  if #dirs > 0 then
    local probe_dir = dirs[#dirs]
    local seen = run.run_blocking(echo_var("PATH"))
    -- Case-insensitive on Windows: SystemRoot-derived candidates and the
    -- inherited PATH can differ in drive-letter/segment casing for the same
    -- directory (`C:\Windows\...` vs `C:\WINDOWS\...`) — cosmetic, not a
    -- functional gap, so the check must not be case-sensitive there.
    local haystack = is_windows and seen.stdout:lower() or seen.stdout
    local needle = is_windows and probe_dir:lower() or probe_dir
    ok(
      haystack:find(needle, 1, true) ~= nil,
      "run_blocking: the completed PATH reaches the subprocess by default — " .. probe_dir
    )
  end

  -- A variable set only via opts.env must reach the subprocess.
  local var_cmd = echo_var("LIB_NVIM_RUN_SPEC_VAR")
  local with_var = run.run_blocking(var_cmd, { env = { LIB_NVIM_RUN_SPEC_VAR = "from-opts-env" } })
  ok(
    with_var.stdout:find("from-opts-env", 1, true) ~= nil,
    "run_blocking: opts.env vars reach the subprocess"
  )

  -- --------------------------------------------------------- env = false opt-out

  -- With enrichment off, a variable set only via opts.env_opts.vars must NOT
  -- silently appear — env = false must skip cross.run.env entirely, not just
  -- skip the vars override.
  local without_var = run.run_blocking(var_cmd, { env = false })
  ok(
    without_var.stdout:find("from-opts-env", 1, true) == nil,
    "run_blocking: env = false opts out of enrichment (no stray var)"
  )

  -- --------------------------------------------------------------- run() async

  local async_done, async_ok, async_res
  run.run("echo async-run-ok", function(o, r)
    async_ok, async_res = o, r
    async_done = true
  end)
  vim.wait(3000, function()
    return async_done
  end, 10)
  ok(async_done, "run: async call completes")
  eq(async_ok, true, "run: a successful async command reports ok")
  ok(async_res.stdout:find("async-run-ok", 1, true) ~= nil, "run: async stdout is captured")

  local async_var_done, async_var_res
  run.run(var_cmd, function(_, r)
    async_var_res = r
    async_var_done = true
  end, { env = { LIB_NVIM_RUN_SPEC_VAR = "from-async-opts-env" } })
  vim.wait(3000, function()
    return async_var_done
  end, 10)
  ok(
    async_var_res.stdout:find("from-async-opts-env", 1, true) ~= nil,
    "run: opts.env vars reach an async subprocess too"
  )
end
