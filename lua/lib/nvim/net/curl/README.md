# `lib.nvim.net.curl`

Async (and blocking) HTTP-via-curl helper with JSON-body decoding — the
shared core behind every plugin that hand-rolls curl-argv-building plus
`vim.system` plus `vim.json.decode`.

Builds a curl argv from `opts` (method, headers, bearer token, query string,
body), spawns it through `vim.system` (Neovim 0.10+ required — no
`jobstart` fallback), and decodes the response body as JSON for you.

## Usage

```lua
local curl = require("lib.nvim.net.curl")

-- async
curl.fetch_json("https://api.example.com/items", {
  method = "GET",
  query = { limit = "10" },
  bearer_token = "abc123",
}, function(ok, data, raw)
  if ok then
    vim.print(data)
  else
    vim.notify("fetch failed: " .. data, vim.log.levels.ERROR)
  end
end)

-- blocking
local ok, data, raw = curl.fetch_json_blocking("https://api.example.com/items", {
  timeout_ms = 5000,
})
```

## Returns

| # | Type                     | Meaning                                                        |
|---|--------------------------|-----------------------------------------------------------------|
| 1 | `boolean`                | `true` if curl exited 0 and the body decoded as JSON            |
| 2 | `any`                    | Decoded JSON on success; an error string on failure              |
| 3 | `vim.SystemCompleted`    | The raw `vim.system` result (`code`, `stdout`, `stderr`, ...)    |

`fetch_json` delivers these three values to `cb`; `fetch_json_blocking`
returns them directly.
