# `lib.nvim.fs.open.url.system_opener`

Open a path or URL with the OS default handler — the per-OS dispatch
(`open` / `xdg-open` / `cmd.exe /c start`) that several plugins were
reimplementing independently before this module existed as a real shared
utility.

`cfg` is entirely optional. Windows support is **on by default**; pass
`cfg.enable_windows_opener = false` to opt back out. `open_cmd_mac`/
`open_cmd_unix` override the mac/Linux command for callers that need
something other than plain `open`/`xdg-open` (e.g. WSL's `wslview`).

## Usage

```lua
local system_opener = require("lib.nvim.fs.open.url.system_opener")

system_opener.open("https://github.com")
system_opener.open("/path/to/file.pdf")

-- Disable the Windows opener explicitly, or override a command:
system_opener.open(url, { enable_windows_opener = false })
system_opener.open(url, { open_cmd_unix = { "wslview", url } })

if system_opener.is_ike("www.example.com") then
  -- looks like a URL
end
```

## Returns

`M.open(url, cfg?)` returns `true` if an opener command was found and
launched (detached, via `jobstart`), `false` if the platform has no known
opener (or the caller explicitly disabled it).

`M.is_ike(s)` is a quick heuristic predicate: true for `http(s)://`,
`file://`, `www.`-prefixed, or bare `name.tld`-shaped strings.
