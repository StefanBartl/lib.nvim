# `lib.nvim.terminal`

Small terminal-buffer helpers: shell-escaping, terminal-buffer detection and
cleanup, and a Kitty-terminal check.

## Usage

```lua
local terminal = require("lib.nvim.terminal")

terminal.escape("my file.txt")   --> "my\\ file.txt"
```

`escape(path)` backslash-escapes spaces and `` $`\ `` for shell use — a
narrow, ad-hoc set of characters, not a full shell-quoting implementation.

```lua
terminal.is_terminal_buf(bufnr)          --> true / false / nil
```

Returns `true`/`false` based on `vim.bo[bufnr].buftype == "terminal"`. The
`nil` branch guards against `buftype` itself coming back falsy (`nil` or
`false`); in practice `vim.bo[bufnr].buftype` is always a string for a valid
buffer and indexing `vim.bo` with an invalid buffer number raises rather than
returning a falsy value, so callers should still validate `bufnr` themselves
(e.g. via `lib.nvim.normalize.buf_valid`) before calling this.

```lua
terminal.delete_terminal_buf(bufnr)      --> true / false / nil
```

Returns `nil` immediately if `bufnr` isn't a number; otherwise attempts
`vim.api.nvim_buf_delete(bufnr, { force = true })` inside `pcall` and returns
whether that succeeded. Note: unlike its doc comment implies, it does **not**
check `is_terminal_buf` first — it force-deletes whatever buffer number it's
given.

```lua
terminal.is_kitty()   --> boolean
```

True if `$KITTY_LISTEN_ON` is set and non-empty, or if `$TERM` contains
`"kitty"`.

---

## `terminal.capabilities` — what can it draw

```lua
local caps = require("lib.nvim.terminal.capabilities")

caps.supports("kitty_graphics")   --> boolean, detected once per session and cached
if caps.require("sixel", { feature = "inline images" }) then ... end
caps.detect({ TERM = "foot" })    --> pure: capabilities of the environment given (tests)
caps.names()                      --> { "kitty_graphics", "osc1337_images", "sixel", "truecolor" }
caps.reset()                      -- forget the cache and the warnings
```

Names: `kitty_graphics` (Kitty, WezTerm, Ghostty, Konsole), `osc1337_images` (WezTerm, iTerm2, Konsole,
from `terminal.host`), `sixel` (foot, mlterm, WezTerm, iTerm2, a `$TERM` naming sixel), `truecolor`
(`$COLORTERM` truecolor/24bit). None has a runtime query: `true` means "known to", `false` "not known to".
`detect` also carries `host` (the recognised terminal, `in_tmux`, the passthrough `hint`).

`require(name, { feature?, notify? })` is `supports` plus **one** warning per missing capability for the
whole session (the message names the feature, the capability, the terminal and the tmux hint): a plugin
that tries to draw on every cursor move does not repeat it a hundred times. `notify` replaces the default
`lib.nvim.notify` WARN.

---

## `terminal.host` — which terminal is this

```lua
local host = require("lib.nvim.terminal.host")
local h = host.detect()      -- reads vim.env; pass a table to test
--> { name = "WezTerm", osc1337 = true, in_tmux = false, hint = nil }
```

`name` is `WezTerm`, `iTerm2`, `Konsole` (these draw OSC 1337, `osc1337 = true`), `Kitty` or
`Windows Terminal` (named, `osc1337 = false`), or `nil`. OSC 1337 has no capability query, so
`osc1337 = false` means "not known to", not "cannot". `in_tmux` is `$TMUX`; then `hint` names
the `allow-passthrough` option without which nothing reaches the outer terminal. `host.in_tmux(env)`
is the same check alone. An empty variable counts as unset.

## `terminal.osc` — build and send escape sequences safely

```lua
local osc = require("lib.nvim.terminal.osc")

osc.sanitize(text, max)               -- control characters -> "?", cut on a character boundary
local seq = osc.user_var("MY_VAR", v) -- OSC 1337 SetUserVar; name validated, value base64
osc.send(osc.wrap(seq))               -- wrap = tmux passthrough envelope when $TMUX is set
```

- `user_var` returns `nil, err` for a name outside `[A-Za-z0-9_]`: the name is spliced in as is.
- `wrap_tmux(seq)` is `ESC P tmux ; <seq with every ESC doubled> ESC \`; `wrap(seq, in_tmux)` applies it
  only in tmux (default: `$TMUX`).
- `send(payload)` writes through `nvim_ui_send` (Neovim 0.12+) in **one** call and returns `ok, err`
  instead of raising. Everything that belongs together must be one `payload`, or Neovim's own
  redraw can land in between. `available()` tells whether the API exists.
