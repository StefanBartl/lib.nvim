---@module 'lib.nvim.cross.uv.spawn_shell_command'
--- Cross-platform helper to spawn shell commands in Neovim using uv.spawn.
--- On Windows, uses cmd.exe; on Linux/macOS, uses /bin/sh.
--- Ensures commands like "npm run dev:server" work reliably.
---@param cmd string Command to run (shell syntax allowed)
---@param args string[] List of arguments (optional, appended to cmd)
---@param opts table Optional table:
---           stdio: uv.spawn stdio table
---           on_exit: callback(code, signal)
return function(cmd, args, opts)
  args = args or {}
  opts = opts or {}

  local uv = vim.loop
  local shell, shell_flag, full_cmd

  if vim.fn.has("win32") == 1 then
    shell = "cmd.exe"
    shell_flag = "/c"
    full_cmd = table.concat(vim.iter({ cmd, args }):flatten(), " ")
    args = { shell_flag, full_cmd }
  else
    shell = "/bin/sh"
    shell_flag = "-c"
    full_cmd = table.concat(vim.iter({ cmd, args }):flatten(), " ")
    args = { shell_flag, full_cmd }
  end

  local handle
  handle = uv.spawn(shell, {
    args = args,
    stdio = opts.stdio or { nil, 1, 2 }, -- default: inherit stdout/stderr
  }, function(code, signal)
    if opts.on_exit then
      opts.on_exit(code, signal)
    else
      print(("Command exited with code %d, signal %s"):format(code, tostring(signal)))
    end
    if handle then handle:close() end
  end)

  return handle
end

-- Usage example:
-- spawn_shell_command("npm", { "run", "dev:server" })
-- spawn_shell_command("echo", { "Hello World" }, { on_exit = function(code) print(code) end })
