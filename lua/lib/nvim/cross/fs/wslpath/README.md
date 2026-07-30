# `lib.nvim.cross.fs.wslpath`

Converts paths between their WSL (unix) and Windows forms via the `wslpath`
binary that ships with every WSL distribution.

Upstreamed from three independent copies of the same private helper the author
had accumulated across plugins — `open.nvim`'s `handlers/filemanager.lua` and
`handlers/default.lua`, plus `lib.nvim.cross.open_default`'s own — which is
exactly the duplication threshold at which a helper belongs in the shared lib.

## Behaviour

Only meaningful inside a WSL session. On any other platform `wslpath` does not
exist, and both converters return `nil` rather than erroring — so a caller can
attempt a conversion unconditionally and read `nil` as "not convertible here".
Callers that want to avoid the spawn entirely should gate on
`lib.nvim.cross.platform.is_wsl` first, which is what `open_default` and
`open.nvim`'s filemanager handler both do.

`nil` is also the correct answer for a Linux-side path with no Windows-side
equivalent (something under `/home`, say) — that is a real result, not a
failure, and callers typically fall back to `xdg-open` there.

Both directions run through `lib.nvim.cross.run_argv.run_blocking_captured`
(an argv table, no shell), so a path containing spaces or shell metacharacters
needs no quoting. The call is blocking by design: the converted path is needed
to build the very next argv, and it is a single sub-millisecond spawn.

## Usage

```lua
local wslpath = require("lib.nvim.cross.fs.wslpath")

-- unix → Windows  (/mnt/c/Users/x → C:\Users\x)
local win = wslpath.to_win("/mnt/c/Users/x")
if win then
  require("lib.nvim.cross.run").run_detached({ "explorer.exe", win })
end

-- Windows → unix  (C:\Users\x → /mnt/c/Users/x)
local unix = wslpath.to_unix([[C:\Users\x]])
```

Gated on the platform, the way callers normally use it:

```lua
local is_wsl = require("lib.nvim.cross.platform.is_wsl")

if is_wsl() then
  local win = require("lib.nvim.cross.fs.wslpath").to_win(path)
  -- nil → no Windows-side equivalent, fall back to xdg-open
end
```

## API

| Function | Returns | Description |
| --- | --- | --- |
| `to_win(unix_path)` | `string\|nil` | `wslpath -w` — WSL/unix path to its Windows equivalent |
| `to_unix(win_path)` | `string\|nil` | `wslpath -u` — Windows path to its WSL/unix equivalent |

Trailing `\r`/`\n` from the binary's output is stripped; an empty result is
normalized to `nil`.

## See also

- [`lib.nvim.cross.open_default`](../../open_default/README.md) — consumer;
  opens a path/URL with the system default application
- [`lib.nvim.cross.fs.separators`](../separators) — pure string separator
  normalization, no subprocess involved
