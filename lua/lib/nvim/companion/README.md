# `lib.nvim.companion`

A **companion window**: the main Neovim opens a SECOND Neovim in its own
terminal window (a second monitor, say). That instance connects back over
msgpack-RPC and shows one read-only buffer whose content the main instance
pushes; keys pressed there run named actions **in the main instance**.

Logic and state stay in the main instance. The companion is display and input
only. First consumer: the dap.nvim memory view (a live hex view beside the
editor).

## Usage

```lua
local companion = require("lib.nvim.companion")

local handle, err = companion.open({
  title = "Memory",                       -- window / buffer title
  lines = { "00000000  00 01 02 ..." },   -- initial content
  highlights = {                          -- optional extmarks (0-based, end exclusive)
    { line = 0, col_start = 0, col_end = 8, group = "Comment" },
  },
  filetype = "xxd",                       -- optional
  actions = {                             -- run in the MAIN instance
    jump = function(addr) ... end,
    page = function(delta) ... end,
  },
  keys = {                                -- companion keymaps (normal mode) -> action
    n = { "page", 1 },                    -- name + fixed arguments
    p = { "page", -1 },
    a = { "jump", prompt = "Address: " }, -- asks (vim.ui.input) and sends the text last
    r = "refresh",                        -- name alone
  },
  on_close = function() end,              -- the companion is gone (once)
  terminal = nil,                         -- argv template, see below; false = headless, no window
  attach_timeout = 15000,                 -- ms until a companion that never attached is closed; false = no limit
})

handle:update(lines, highlights)   -- replace the content (the companion keeps its cursor line)
handle:set_title("Memory 0x7ffe")  -- window title + status line
handle:is_open()                   -- false once closed or gone
handle:is_attached()               -- the companion has connected (content is shown)
handle:close()                     -- closes the companion window / process; idempotent

companion.handles()                -- every open handle
companion.close_all()
```

`open` returns `nil, err` for invalid options (a line with a newline, a key
without an action, ...), when no RPC server can be started, when no terminal is
found, or when the process cannot be started; nothing is left behind then.
`update` and `set_title` before the companion attached are kept and go with
the first render. `q` in the companion closes it (unless `keys.q` is given).
A companion that has not reported in after `attach_timeout` ms (default
`protocol.ATTACH_TIMEOUT_MS` = 15 s; a terminal that never ran the inner
`nvim`, say) is closed by the liveness check: the process is ended when it
was started directly, `on_close` runs, a warning says so.

## Terminal defaults

`terminal` is an argv template around the inner `nvim` command. Placeholders:
`{cmd}` (a whole element: the inner argv spliced in), `{title}`, `{shell}` (the
inner command as one POSIX-quoted line, inside an element), `{applescript}`
(that line as an AppleScript string literal). Without it, per platform:

| Platform | Default                                                                 |
| -------- | ----------------------------------------------------------------------- |
| Windows  | `wt.exe -w new new-tab --title {title} {cmd}`; else `cmd.exe /c start "" {cmd}` |
| macOS    | `$TERMINAL` when installed (see below); else Terminal.app through `osascript` (`do script {applescript}`) |
| Linux    | `$TERMINAL`; else the first of `x-terminal-emulator`, `gnome-terminal`, `konsole`, `xterm` |

The `cmd.exe` fallback passes an EMPTY title element on purpose: `start`
takes its first *quoted* argument as the window title, and libuv quotes an
argument only when it is empty or holds whitespace, so a one-word title
(`Memory`) would reach `start` bare and be taken as the program to run. The
companion sets its own window title (`'titlestring'`) anyway.

`$TERMINAL` is mapped by its basename (`launch.terminal_template`): terminals
whose `-e` takes the rest of the argv (kitty, alacritty, foot, wezterm, xterm,
konsole, st, urxvt, ...) get `-e {cmd}`; `gnome-terminal` gets `-- {cmd}`;
`xfce4-terminal`, `mate-terminal`, `terminator` and `tilix`, whose `-e` takes
ONE string, get `-e {shell}`.

The choice is `launch.default_terminal(env)`, a pure function of an env table
(`os`, `executable`, `TERMINAL`), tested without a window. The inner command is
`<v:progpath> -u NONE -i NONE -n --cmd "set rtp^=<lib.nvim root>" --cmd "lua
require('lib.nvim.companion.client').start({ server = [[<main servername>]], id = <id> })"`
(`launch.inner_argv`); the server name travels as a Lua long string so no
quote or backslash pair has to survive a launcher's re-parsing.

`terminal = false` starts the companion with `--headless` and no window at
all: that is what the integration spec and scripts use.

## Mechanics and lifecycle

1. The main instance makes sure it has an RPC server (`v:servername`, else
   `serverstart()`), registers a handle (state `pending`) and starts the
   terminal with `vim.system(argv, { detach = true })`. `vim.system`, not
   `jobstart`: `jobstart` (and `vim.fn.executable()`) refuse a Windows App
   Execution Alias, and `wt.exe` of a Store / winget Windows Terminal is one
   (a 0-byte reparse point under `%LOCALAPPDATA%\Microsoft\WindowsApps`);
   `uv.spawn` runs it. `companion.is_runnable(name, windows)` is the check
   the terminal choice uses (`executable()`, else that alias folder).
2. The companion (`client.lua`, in the second Neovim) connects to the main
   (`sockconnect("pipe", server, { rpc = true })`), starts its own server and
   calls `companion._attach(id, its_servername)` over `nvim_exec_lua`. The
   answer is the title, filetype and keys (`{ closed = true }` when the handle
   is already gone: the companion quits).
3. The main connects back (scheduled, after answering: the companion is
   blocked in that request) and pushes the content with `rpcnotify` of
   `nvim_exec_lua` → `client.render(payload)`. Every later `update` /
   `set_title` is one such message.
4. A key in the companion is `rpcnotify` → `companion._action(id, name, args)`;
   the action runs in the main instance, an error is a `vim.notify` there.
5. The companion leaving (`q`, `:qa!`) tells the main (`_detach`, a
   notification on `VimLeavePre`, followed by a 100 ms wait so the write is
   on the wire before the exit cancels it); the main drops the channel and
   calls `on_close`. A companion that was killed is noticed by a 1 s liveness
   check of its channel. A main that died is noticed by the companion the
   same way: it quits.
6. `handle:close()` tells the companion to quit (a notification; a companion
   in state `attaching`, whose channel back is not open yet, is connected
   first so it is told as well), closes the channel, stops the process when
   it was started directly, calls `on_close` once. On the main's `VimLeavePre`
   every open companion is closed the same way, with the same short wait for
   the writes.

**Never a blocking request across the two channels.** The main and a
companion hold one channel in each direction, and Neovim only serves the
channel it is blocked on. A `quit` sent as `rpcrequest` by the main while
the companion is blocked in its own `rpcrequest(_detach)` (it pressed `q`
while the main was busy in a DAP step or a render) would leave both
editors frozen for good -- no timeout, no error. Every message after the
companion's initial `_attach` (made before the main has a channel to it) is
therefore `rpcnotify`; the transport has no `request` at all, and a lost
notification is covered by the liveness checks on both sides.

Everything is idempotent and guarded: a push to a dead companion ends as a
detach, never as an error in the caller. Only the main's own server name is
used; no TCP sockets.

## Layers

- `protocol.lua`: handle registry, messages, attach / connect / action /
  detach dispatch, the liveness check (dead channels, attach timeout). Talks
  through a `Lib.Companion.Transport` (`connect`, `notify`, `alive`, `close`;
  no `request`), so the specs run it against a fake that records every
  message, no process involved.
- `launch.lua`: the argv (pure).
- `init.lua`: the RPC transport, the job, the liveness timer, `VimLeavePre`.
- `client.lua`: the companion side.

## Not supported

- Editing in the companion: the buffer is `nofile`, `modifiable=false`, no
  swap, no undo. Content changes only through `update`.
- More than one buffer or window per companion, or a companion without a
  main instance.
- Keys in modes other than normal mode.
- A companion on another machine (no TCP).

## Manual check

`nvim --headless -u NONE -l scripts/companion_manual.lua` from the repo root
opens a real companion in the platform's terminal, pushes updates, triggers an
action from the companion side and closes it (`COMPANION_MANUAL_KEEP=1` leaves
the window open until `q`).
