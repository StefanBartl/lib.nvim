-- TESTS/support/shell_models.lua -- small models of how the target programs read a quoted word, so a
-- spec can check that quoting survives the round trip instead of comparing strings.
--
--   posix(line)   one word out of a POSIX single-quote line (as security_spec always did)
--   fish(line)    fish: inside '...' a backslash escapes `\` and `'`, any other backslash is literal
--   msvcrt(line)  the C runtime's argv rules (what a program started from cmd.exe receives):
--                 2n backslashes + quote -> n backslashes and the quote toggles,
--                 2n+1 backslashes + quote -> n backslashes and a literal quote,
--                 inside quotes `""` is a literal quote, white space outside quotes splits
--   received_args(shell, to_line, words, prefix)
--                 not a model: the REAL thing. Types a quoted line into a real shell and returns the
--                 arguments a real program received (PowerShell's native argument passing differs
--                 between versions, so no model of it would be trusted)
--   installed(exe) whether a program is on the PATH, without the slow scan of a WSL host (see below)

local M = {}

--- Whether `exe` can be started from the PATH. It decides which real-shell cases get registered, and
--- that happens while a spec file is collected, so it must be cheap.
---
--- `vim.fn.executable` looks through every PATH entry, and a miss costs seconds on a WSL host: the
--- Windows PATH is on it (`/mnt/c/...`, a 9p mount where every lookup is a round trip to Windows),
--- and a spec file that asks for a shell that is not installed (`pwsh`, `zsh`) ran into the
--- 10 s limit of a case before its first case even started. A program found through such an entry
--- is a Windows program (`pwsh.exe` is never called `pwsh` there) that the Linux Neovim cannot
--- start by the paths these specs hand over, so on a WSL host those entries are not looked at.
---
--- A WSL host is told by the kernel's name (`...-microsoft-standard-WSL2`), not by
--- `$WSL_DISTRO_NAME`: the spec runner may start its children with a cleaned environment.
---@param exe string
---@return boolean
function M.installed(exe)
  local on_wsl = (vim.uv.os_uname().release or ""):lower():find("microsoft", 1, true) ~= nil
  if vim.fn.has("win32") == 1 or not on_wsl then
    return vim.fn.executable(exe) == 1
  end
  for dir in vim.gsplit(vim.env.PATH or "", ":", { plain = true }) do
    if dir ~= "" and not vim.startswith(dir, "/mnt/") then
      local path = dir .. "/" .. exe
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "file" and vim.uv.fs_access(path, "X") then
        return true
      end
    end
  end
  return false
end

--- Words of a line quoted with single quotes only (the POSIX form; backslash is literal).
---@param line string
---@return string[]
function M.posix(line)
  local words, i, n = {}, 1, #line
  while i <= n do
    while i <= n and line:sub(i, i) == " " do
      i = i + 1
    end
    if i > n then
      break
    end
    local word = {}
    while i <= n and line:sub(i, i) ~= " " do
      local c = line:sub(i, i)
      if c == "'" then
        local close = line:find("'", i + 1, true)
        assert(close, "unterminated quote in: " .. line)
        word[#word + 1] = line:sub(i + 1, close - 1)
        i = close + 1
      elseif c == "\\" then
        word[#word + 1] = line:sub(i + 1, i + 1)
        i = i + 2
      else
        word[#word + 1] = c
        i = i + 1
      end
    end
    words[#words + 1] = table.concat(word)
  end
  return words
end

--- Words of a fish line.
---@param line string
---@return string[]
function M.fish(line)
  local words, i, n = {}, 1, #line
  while i <= n do
    while i <= n and line:sub(i, i) == " " do
      i = i + 1
    end
    if i > n then
      break
    end
    local word = {}
    while i <= n and line:sub(i, i) ~= " " do
      local c = line:sub(i, i)
      if c == "'" then
        i = i + 1
        while true do
          assert(i <= n, "unterminated quote in: " .. line)
          local q = line:sub(i, i)
          if q == "'" then
            i = i + 1
            break
          elseif
            q == "\\" and (line:sub(i + 1, i + 1) == "\\" or line:sub(i + 1, i + 1) == "'")
          then
            word[#word + 1] = line:sub(i + 1, i + 1)
            i = i + 2
          else
            word[#word + 1] = q
            i = i + 1
          end
        end
      else
        word[#word + 1] = c
        i = i + 1
      end
    end
    words[#words + 1] = table.concat(word)
  end
  return words
end

--- Arguments of a command line read by the C runtime.
---@param line string
---@return string[]
function M.msvcrt(line)
  local args, current, in_quotes, started = {}, {}, false, false
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == "\\" then
      local j = i
      while line:sub(j, j) == "\\" do
        j = j + 1
      end
      local count = j - i
      if line:sub(j, j) == '"' then
        current[#current + 1] = string.rep("\\", math.floor(count / 2))
        if count % 2 == 1 then
          current[#current + 1] = '"'
          j = j + 1
        end
      else
        current[#current + 1] = string.rep("\\", count)
      end
      i = j
      started = true
    elseif c == '"' then
      if in_quotes and line:sub(i + 1, i + 1) == '"' then
        current[#current + 1] = '"'
        i = i + 2
      else
        in_quotes = not in_quotes
        i = i + 1
      end
      started = true
    elseif c:find("%s") and not in_quotes then
      if started then
        args[#args + 1] = table.concat(current)
        current, started = {}, false
      end
      i = i + 1
    else
      current[#current + 1] = c
      started = true
      i = i + 1
    end
  end
  if started then
    args[#args + 1] = table.concat(current)
  end
  return args
end

--- The program `received_args` starts: it writes the arguments it got after the output path as
--- JSON to that path.
local DUMP_SCRIPT = {
  "local out = arg[1]",
  "local rest = {}",
  "for i = 2, #arg do",
  "  rest[#rest + 1] = arg[i]",
  "end",
  "vim.fn.writefile({ vim.json.encode(rest) }, out)",
}

--- The arguments a real program receives when a real shell runs a quoted command line.
---
--- The program is this very Neovim, started as `nvim -l <script> <out> <words...>`: it is always
--- there, it reads its command line the way any Windows program does (C runtime), and it writes
--- what it got to a file. One shell process serves all `words`.
---@param shell string[] The shell command; the command line is appended as its last element
---@param to_line fun(argv: string[]): string|nil Quotes an argv for that shell
---@param words string[] The words to hand to the program
---@param prefix? string Typed in front of the line (a PowerShell preference variable)
---@return string[]|nil received nil when the program wrote nothing
---@return string diagnostics What the line was and what the shell printed, for a failure message
function M.received_args(shell, to_line, words, prefix)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local script, out = dir .. "/dump.lua", dir .. "/args.json"
  vim.fn.writefile(DUMP_SCRIPT, script)
  local argv = { vim.v.progpath, "--headless", "--clean", "-i", "NONE", "-l", script, out }
  vim.list_extend(argv, words)
  local line = (prefix or "") .. assert(to_line(argv))
  local command = vim.list_extend(vim.deepcopy(shell), { line })
  local res = vim.system(command, {}):wait(60000)
  local received
  if vim.fn.filereadable(out) == 1 then
    received = vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
  end
  vim.fn.delete(dir, "rf")
  local diagnostics = ("line: %s\nexit %s\nstdout: %s\nstderr: %s"):format(
    line,
    tostring(res.code),
    res.stdout or "",
    res.stderr or ""
  )
  return received, diagnostics
end

return M
