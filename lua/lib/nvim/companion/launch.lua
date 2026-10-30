---@module 'lib.nvim.companion.launch'
--- The argv of a companion: the inner `nvim` command and the terminal window around it.
---
--- Everything here is pure (no `vim.fn`, no process): the terminal choice is a
--- function of a `Lib.Companion.LaunchEnv` table, so the defaults per platform
--- are unit-tested without opening a window. `lib.nvim.companion` fills the env
--- from the running instance.
---
--- A terminal is an argv template. The placeholders:
---   `{cmd}`         a whole element: replaced by the inner argv (spliced in)
---   `{shell}`       inside an element: the inner argv as ONE POSIX-quoted line
---   `{applescript}` inside an element: that line as an AppleScript string literal
---   `{title}`       inside an element: the companion title

local shell_quote = require("lib.nvim.cross.shell_quote")

local M = {}

M.CLIENT_MODULE = "lib.nvim.companion.client"

---A Lua long-string literal for `s`; `nil` when `s` cannot be held by one
---(`]]` inside). Long strings need no escaping, which keeps the command line
---free of quotes and backslash pairs that a terminal launcher may re-parse
---(Windows pipe names are full of backslashes).
---@param s string
---@return string|nil
function M.lua_literal(s)
  if s:find("]]", 1, true) then
    return nil
  end
  return "[[" .. s .. "]]"
end

---The value for `:set rtp^=`: forward slashes, `\`, space and comma escaped.
---@param path string
---@return string
function M.rtp_value(path)
  local p = path:gsub("\\", "/"):gsub("/+$", "")
  return (p:gsub("[ ,\\]", "\\%0"))
end

---The inner command: the `nvim` that becomes the companion. Pure.
---@param opts Lib.Companion.InnerOpts
---@return string[]|nil argv
---@return string|nil err
function M.inner_argv(opts)
  local server = M.lua_literal(opts.server)
  if not server then
    return nil, "servername cannot be passed as a Lua literal: " .. opts.server
  end
  if type(opts.id) ~= "number" or opts.id ~= math.floor(opts.id) then
    return nil, "id must be an integer"
  end
  local argv = { opts.progpath, "-u", "NONE", "-i", "NONE", "-n" }
  if opts.headless then
    argv[#argv + 1] = "--headless"
  end
  argv[#argv + 1] = "--cmd"
  argv[#argv + 1] = "set rtp^=" .. M.rtp_value(opts.root)
  argv[#argv + 1] = "--cmd"
  argv[#argv + 1] = ("lua require('%s').start({ server = %s, id = %d })"):format(
    M.CLIENT_MODULE,
    server,
    opts.id
  )
  return argv
end

---Terminals whose `-e` takes the command as ONE string (parsed like a shell
---line), not as the rest of the argv. gnome-terminal has `--` for the argv
---form; the others get the inner command as a `{shell}` line.
local ONE_STRING_E = {
  ["xfce4-terminal"] = true,
  ["mate-terminal"] = true,
  ["terminator"] = true,
  ["tilix"] = true,
}

---The template for `$TERMINAL`: `-e {cmd}` for a terminal that takes the
---command as the rest of its argv (kitty, alacritty, foot, wezterm, xterm,
---konsole, st, urxvt, ...), `-- {cmd}` for gnome-terminal, `-e {shell}` for
---the ones listed in `ONE_STRING_E`. Pure.
---@param term string # the value of $TERMINAL (a name or a path)
---@return string[]
function M.terminal_template(term)
  local base = term:match("([^/\\]+)$") or term
  if base == "gnome-terminal" then
    return { term, "--title", "{title}", "--", "{cmd}" }
  end
  if ONE_STRING_E[base] then
    return { term, "-e", "{shell}" }
  end
  return { term, "-e", "{cmd}" }
end

---The default terminal template for `env`, or `nil, err` when none is found. Pure.
---
---Windows: Windows Terminal (`wt.exe`, a new window with the title), else
---`cmd.exe /c start "" {cmd}` (the title element is EMPTY on purpose: `start`
---takes its first quoted argument as the title, and libuv only quotes an
---argument with whitespace or an empty one, so a one-word title would reach
---`start` bare and be taken as the program; the companion sets its own window
---title anyway). macOS: `$TERMINAL` (`terminal_template`), else Terminal.app
---through `osascript`. Linux: `$TERMINAL`, then the first of
---`x-terminal-emulator`, `gnome-terminal`, `konsole`, `xterm`.
---@param env Lib.Companion.LaunchEnv
---@return string[]|nil template
---@return string|nil err
function M.default_terminal(env)
  local has = env.executable
  local term = env.TERMINAL
  if term == "" then
    term = nil
  end
  if env.os == "windows" then
    if has("wt.exe") or has("wt") then
      return { "wt.exe", "-w", "new", "new-tab", "--title", "{title}", "{cmd}" }
    end
    if has("cmd.exe") or has("cmd") then
      return { "cmd.exe", "/c", "start", "", "{cmd}" }
    end
    return nil, "no terminal found (wt.exe, cmd.exe)"
  end
  if term and has(term) then
    return M.terminal_template(term)
  end
  if env.os == "macos" then
    if has("osascript") then
      return {
        "osascript",
        "-e",
        'tell application "Terminal" to do script {applescript}',
        "-e",
        'tell application "Terminal" to activate',
      }
    end
    return nil, "no terminal found ($TERMINAL, osascript)"
  end
  if has("x-terminal-emulator") then
    return { "x-terminal-emulator", "-T", "{title}", "-e", "{cmd}" }
  end
  if has("gnome-terminal") then
    return { "gnome-terminal", "--title", "{title}", "--", "{cmd}" }
  end
  if has("konsole") then
    return { "konsole", "-e", "{cmd}" }
  end
  if has("xterm") then
    return { "xterm", "-T", "{title}", "-e", "{cmd}" }
  end
  return nil, "no terminal found ($TERMINAL, x-terminal-emulator, gnome-terminal, konsole, xterm)"
end

---An AppleScript string literal (`"`, `\` escaped).
---@param s string
---@return string
function M.applescript_literal(s)
  return '"' .. s:gsub('[\\"]', "\\%0") .. '"'
end

---Expand `template` around `inner`. Pure.
---
---Fails when the template is not a non-empty list of strings, holds no `{cmd}`
---/ `{shell}` / `{applescript}`, or the inner argv cannot be quoted for a shell
---(`{shell}`, `{applescript}`: a control character in an argument).
---@param template string[]
---@param inner string[]
---@param title string
---@return string[]|nil argv
---@return string|nil err
function M.expand(template, inner, title)
  if type(template) ~= "table" or #template == 0 then
    return nil, "terminal must be a non-empty list"
  end
  local out, used = {}, false
  local line
  for _, el in ipairs(template) do
    if type(el) ~= "string" then
      return nil, "terminal holds a non-string"
    end
    if el == "{cmd}" then
      for _, a in ipairs(inner) do
        out[#out + 1] = a
      end
      used = true
    else
      local s = el:gsub("{title}", function()
        return title
      end)
      if s:find("{shell}", 1, true) or s:find("{applescript}", 1, true) then
        if not line then
          local err
          line, err = shell_quote.argv_to_line(inner, "posix")
          if not line then
            return nil, "cannot quote the command for a shell: " .. tostring(err)
          end
        end
        s = s:gsub("{shell}", function()
          return line
        end)
        s = s:gsub("{applescript}", function()
          return M.applescript_literal(line)
        end)
        used = true
      end
      out[#out + 1] = s
    end
  end
  if not used then
    return nil, "terminal has no {cmd}, {shell} or {applescript}"
  end
  return out
end

---The whole argv: inner command inside the terminal (`template`, or the
---platform default from `env`). Pure.
---@param opts Lib.Companion.InnerOpts
---@param template string[]|nil
---@param env Lib.Companion.LaunchEnv
---@param title string
---@return string[]|nil argv
---@return string|nil err
function M.argv(opts, template, env, title)
  local inner, err = M.inner_argv(opts)
  if not inner then
    return nil, err
  end
  if not template then
    template, err = M.default_terminal(env)
    if not template then
      return nil, err
    end
  end
  return M.expand(template, inner, title)
end

return M
