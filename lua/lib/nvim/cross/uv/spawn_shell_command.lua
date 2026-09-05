---@module 'lib.nvim.cross.uv.spawn_shell_command'
--- Cross-platform helper to spawn shell commands in Neovim using uv.spawn.
--- On Windows, uses cmd.exe; on Linux/macOS, uses /bin/sh.
--- Ensures commands like "npm run dev:server" work reliably.
---
--- SECURITY: `cmd`/`args` are joined with spaces and handed to a real shell
--- (`cmd.exe /c` / `sh -c`), on purpose — that is what lets shell syntax
--- (`&&`, pipes, env-var expansion) work. That also means neither may ever
--- be built from a value this process does not already trust (search text,
--- a filename, a branch name, anything an external source produced): a
--- shell metacharacter in it changes what actually runs, exactly the
--- pattern SEC-01/SEC-03 exist to rule out. A caller that only needs a
--- fixed argv with no shell features should reach for
--- `lib.nvim.cross.uv.spawn_capture`/`spawn_stream` (argv, no shell)
--- instead.
---@param cmd string Command to run (shell syntax allowed)
---@param args string[] List of arguments (optional, appended to cmd)
---@param opts table Optional table:
---           cwd: string|nil - working directory (inherits the editor's cwd if nil)
---           stdio: uv.spawn stdio table
---           on_exit: callback(code, signal)
---@return (uv.uv_process_t)? handle uv.spawn handle
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
  -- luv's own meta declares every uv.spawn option required (cwd, env, uid,
  -- gid, verbatim, detached, hide), which no real caller passes.
  ---@diagnostic disable-next-line: missing-fields
  handle = uv.spawn(shell, {
    args = args,
    cwd = opts.cwd,
    stdio = opts.stdio or { nil, 1, 2 }, -- default: inherit stdout/stderr
  }, function(code, signal)
    if opts.on_exit then
      opts.on_exit(code, signal)
    else
      print(("Command exited with code %d, signal %s"):format(code, tostring(signal)))
    end
    if handle then
      handle:close()
    end
  end)

  return handle
end

-- Usage example:
-- spawn_shell_command("npm", { "run", "dev:server" })
-- spawn_shell_command("echo", { "Hello World" }, { on_exit = function(code) print(code) end })
