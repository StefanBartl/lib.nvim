# `lib.nvim.cross.shell_quote`

Pure shell quoting for text that is **typed into a terminal** as one line. Everything that reaches a
shell as a line must be quoted for *that* shell: a name with a space, `;`, `$(...)`, a backtick or a
quote would otherwise be interpreted instead of passed.

```lua
local q = require("lib.nvim.cross.shell_quote")

local kind = q.shell_kind(vim.o.shell)            --> "posix" | "fish" | "powershell" | "cmd" | "portable"
local line, err = q.argv_to_line({ "git", "commit", "-m", "it's a test" }, kind)
--> posix:      git commit -m 'it'\''s a test'
--> powershell: git commit -m 'it''s a test'
```

- `shell_kind(shell)` takes an executable name, a path (spaces allowed) or a command string with
  arguments (`pwsh -NoLogo`). Unknown shells (`nu`, `csh`, ...) are treated as POSIX; `"portable"` is
  the kind to use when the shell is unknown (a multiplexer's default shell): only letters, digits and
  `. _ / : -` pass.
- `argv_to_line(argv, kind)` quotes every word; PowerShell gets the call operator `&` when the program
  word itself is quoted. `word(s, kind, program)` is the single word.
- A word that cannot be represented safely is **refused** (`nil, err`), never guessed at: control
  characters (line break, TAB, NUL, ESC) in every family, `%` for cmd.exe, a double quote or a trailing
  backslash after white space, the empty word and `--%` for PowerShell, an argv with a hole.
- `arg_count(argv)` is the highest positive integer index: `#` and `ipairs` stop at the first hole and
  would lose the words after it without a sound.

`lib.nvim.terminal.escape` is the older, weaker helper (backslash-escapes spaces and `` $`\ `` only);
prefer this module when a line is typed into a terminal.

Specs: `TESTS/shell_quote_spec.lua` (models of how each target reads the word back; real bash/zsh where
installed). The property specs and the round trip through a real PowerShell live in terminal.nvim.
