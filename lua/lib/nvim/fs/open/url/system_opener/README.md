# `lib.nvim.fs.open.url.system_opener`

Open a path or URL with the OS default handler — the per-OS dispatch
(`open` / `xdg-open` / `wslview` / `cmd.exe /c start`) that several plugins were
reimplementing independently before this module existed as a real shared
utility.

## Dispatch order

1. **`vim.ui.open`** (Neovim 0.10+) — the shell-independent, upstream-maintained
   path. Used unless `cfg.prefer_ui_open == false` or `cfg.on_exit` is set.
   If it errors or reports no usable opener, dispatch falls through to (2).
2. **A per-OS argv list**, never a shell string. The list form is deliberate:
   the string form goes through `&shell` + `shellescape`, which quotes paths
   containing spaces incorrectly under `shell=pwsh` on Windows.
3. **WSL** gets `wslview` (which hands the URL to the Windows host) ahead of
   `xdg-open`, since a WSL distro usually has no desktop for `xdg-open` to talk
   to. Only used when `wslview` is actually executable.

`cfg` is entirely optional. Windows support is **on by default**; pass
`cfg.enable_windows_opener = false` to opt back out.

## Usage

```lua
local system_opener = require("lib.nvim.fs.open.url.system_opener")

system_opener.open("https://github.com")
system_opener.open("/path/to/file.pdf")

-- Force the argv dispatch, bypassing vim.ui.open:
system_opener.open(url, { prefer_ui_open = false })

-- Disable the Windows opener explicitly, or override a command:
system_opener.open(url, { enable_windows_opener = false })
system_opener.open(url, { open_cmd_unix = { "gio", "open", "<url>" } })

-- Observe the real exit code (runs attached, skips vim.ui.open):
system_opener.open(url, {
  on_exit = function(code)
    if code ~= 0 then
      vim.notify("opener exited " .. code, vim.log.levels.WARN)
    end
  end,
})

if system_opener.is_like("www.example.com") then
  -- looks like a URL
end
```

In a custom command array, the literal `"<url>"` is substituted with the URL.

## Config — `AutoCmds.General.MD.GotoFile.Cfg`

| Field                   | Type              | Default              | Meaning                                                        |
|-------------------------|-------------------|----------------------|----------------------------------------------------------------|
| `prefer_ui_open`        | `boolean?`        | `true`               | Try `vim.ui.open` first. Ignored when `on_exit` is set.         |
| `enable_windows_opener` | `boolean?`        | `true`               | Enable the `cmd.exe /c start` opener.                           |
| `open_cmd_mac`          | `string[]?`       | `{ "open", url }`    | Override the macOS command.                                     |
| `open_cmd_unix`         | `string[]?`       | `{ "xdg-open", url }`| Override the Linux command.                                     |
| `open_cmd_wsl`          | `string[]?`       | `{ "wslview", url }` | Override the WSL command.                                       |
| `on_exit`               | `fun(code)?`      | none                 | Observe the exit code; runs attached, skips `vim.ui.open`.      |

## Returns

`M.open(url, cfg?)` returns `true` when an opener was **dispatched**, `false`
when the platform has no known opener (or the caller disabled it). Without
`cfg.on_exit` the job is detached and fire-and-forget, so `true` says nothing
about whether the target actually opened — use `on_exit` when that matters.

`M.is_like(s)` is a quick heuristic predicate: true for `http(s)://`, `file://`,
`www.`-prefixed, or bare `name.tld`-shaped strings.

> `M.is_ike` is a misspelling from the original module and remains as a
> deprecated alias of `M.is_like`. New code should use `is_like`.
