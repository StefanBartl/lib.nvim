---@module 'lib.nvim.cross.uv.spawn_command'
--- Cross-platform shell-command runner on raw `uv.spawn`: wraps the command
--- with `cmd.exe /c` on Windows (needed for batch files and shell syntax) or
--- `/bin/sh -c` elsewhere. `cwd` defaults to Neovim's cwd; stdout/stderr are
--- inherited unless `opts.stdio` overrides; `opts.on_exit` observes completion.
---
--- SECURITY: `cmd`/`args` are flattened and joined with spaces, then handed
--- to a real shell (`cmd.exe /c` / `sh -c`) — on purpose, since that is what
--- makes shell syntax (`&&`, pipes, env-var expansion) work. That also means
--- neither may ever be built from a value this process does not already
--- trust (search text, a filename, a branch name, anything an external
--- source produced): a shell metacharacter in it changes what actually
--- runs, exactly the pattern SEC-01/SEC-03 exist to rule out. A caller that
--- only needs a fixed argv with no shell features should reach for
--- `lib.nvim.cross.uv.spawn_capture`/`spawn_stream` (argv, no shell)
--- instead.
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
  -- luv's own meta declares every uv.spawn option required (cwd, env, uid,
  -- gid, verbatim, detached, hide), which no real caller passes.
  ---@diagnostic disable-next-line: missing-fields
  handle = uv.spawn(shell, {
    args = shell_args,
    cwd = cwd,
    stdio = stdio,
  }, function(code, signal)
    if on_exit then
      on_exit(code, signal)
    else
      vim.schedule(function()
        print(
          ("Command '%s' exited with code %d, signal %s"):format(full_cmd, code, tostring(signal))
        )
      end)
    end
    if handle then
      handle:close()
    end
  end)

  return handle
end

return {
  spawn_project_command = spawn_project_command,
}
