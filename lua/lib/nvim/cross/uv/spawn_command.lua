---@module 'lib.nvim.cross.uv.spawn_command'
--- Cross-platform shell command runner for Neovim/Lua.
---
--- This module provides a helper function `spawn_project_command` that executes shell commands
--- in a way that works reliably across platforms (Windows, Linux, macOS) and correctly handles
--- project-relative paths, especially in Node.js projects.
---
--- Features:
--- 1. Detects platform and automatically selects the appropriate shell:
---    - Windows: `cmd.exe /c`
---    - Linux/macOS: `/bin/sh -c`
--- 2. Supports absolute or project-relative paths for the working directory.
--- 3. Pipes stdout/stderr to Neovim by default, but allows custom `stdio` configuration.
--- 4. Provides an `on_exit` callback for asynchronous process completion handling.
---
--- Usage scenarios:
--- - Running `npm run dev` inside a Node.js project folder, with cwd automatically resolved.
--- - Executing shell commands relative to a project root (absolute or relative path).
--- - Cross-platform scripting without needing to manually handle Windows `.cmd` files or shell specifics.
---
--- Design decisions:
--- - On Windows, `uv.spawn` cannot execute batch files or shell syntax directly. Wrapping commands
---   with `cmd.exe /c` ensures that scripts and shell features work.
--- - On Unix systems, many executables are direct binaries or scripts with shebangs, so they
---   can often be executed directly. Wrapping with `/bin/sh -c` provides consistency.
--- - cwd handling allows commands to be run relative to a project root or Neovim buffer directory.
--- - stdout/stderr piping and callback mechanism make this suitable for asynchronous usage
---   in Neovim or CLI utilities.
---

local uv = vim.loop

---@param cmd string Command to execute (shell syntax allowed)
---@param opts table Optional configuration:
---   cwd: string|nil - working directory; if nil, uses current buffer/project root
---   args: string[]|nil - extra arguments appended to cmd
---   stdio: table|nil - uv.spawn stdio configuration
---   on_exit: fun(code:number, signal:number)|nil - callback when process exits
---@return (uv.uv_process_t)? # handle uv.spawn handle
local function spawn_project_command(cmd, opts)
  opts = opts or {}
  local args = opts.args or {}
  local cwd = opts.cwd or vim.fn.getcwd() -- fallback to Neovim cwd if not specified
  local stdio = opts.stdio or { nil, 1, 2 } -- default: inherit stdout/stderr
  local on_exit = opts.on_exit

  -- Flatten the command and arguments for shell execution
  local full_cmd = table.concat(vim.iter({ cmd, args }):flatten():totable(), " ")

  local shell, shell_args

  -- Detect platform
  if vim.fn.has("win32") == 1 then
    -- Windows: use cmd.exe to interpret batch files and shell syntax
    shell = "cmd.exe"
    shell_args = { "/c", full_cmd }
  else
    -- Unix: use /bin/sh for consistency with shell features
    shell = "/bin/sh"
    shell_args = { "-c", full_cmd }
  end

  -- Spawn the process asynchronously
  local handle
  handle = uv.spawn(shell, {
    args = shell_args,
    cwd = cwd,
    stdio = stdio,
  }, function(code, signal)
    if on_exit then
      on_exit(code, signal)
    else
      vim.schedule(function()
        print(("Command '%s' exited with code %d, signal %s"):format(full_cmd, code, tostring(signal)))
      end)
    end
    if handle then handle:close() end
  end)

  return handle
end

-- Example usage:
-- spawn_project_command("npm run dev", { cwd = "/path/to/project", on_exit = function(code) print(code) end })
-- spawn_project_command("echo", { args = { "Hello World" } })
return {
  spawn_project_command = spawn_project_command,
}
