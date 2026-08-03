# `lib.nvim.net.curl`

Async (and blocking) HTTP-via-curl helper — the shared core behind every
plugin that hand-rolls curl-argv-building plus `vim.system`. Two tiers:
`fetch_json`/`fetch_json_blocking` decode the response body as JSON for you;
`fetch_raw`/`fetch_raw_blocking` return the response verbatim — status,
headers and body, undecoded — for a caller that needs to *show* the
response, or one whose content type is not JSON at all.

Builds a curl argv from `opts` (method, headers, bearer token, query string,
body), spawns it through `vim.system` (Neovim 0.10+ required — no
`jobstart` fallback).

## Usage

```lua
local curl = require("lib.nvim.net.curl")

-- JSON tier, async
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

-- JSON tier, blocking
local ok, data, raw = curl.fetch_json_blocking("https://api.example.com/items", {
  timeout_ms = 5000,
})

-- Raw tier, blocking — status/headers/body, no JSON assumed
local ok2, resp = curl.fetch_raw_blocking("https://api.example.com/items")
if ok2 then
  print(resp.status, resp.status_text)   -- 200  OK
  print(resp.headers["content-type"])
  print(resp.body)                       -- exactly as received
end
```

## Why curl's own exit code is not the HTTP status

curl exits `0` for a *successful request*, regardless of what the server
answered — a `404` is still exit `0`, because the request itself worked.
`fetch_raw`/`fetch_raw_blocking` parse the status out of the response's own
status line instead; `resp.status` is the only reliable source for it.
`ok = false` from either function means curl itself failed (unreachable
host, timeout, a malformed response) — a materially different failure from
"the server answered 404," which is `ok = true` with `resp.status == 404`.

## Returns

**`fetch_json` / `fetch_json_blocking`**

| # | Type                     | Meaning                                                        |
|---|--------------------------|-----------------------------------------------------------------|
| 1 | `boolean`                | `true` if curl exited 0 and the body decoded as JSON            |
| 2 | `any`                    | Decoded JSON on success; an error string on failure              |
| 3 | `vim.SystemCompleted`    | The raw `vim.system` result (`code`, `stdout`, `stderr`, ...)    |

**`fetch_raw` / `fetch_raw_blocking`**

| # | Type                              | Meaning                                                    |
|---|-----------------------------------|-------------------------------------------------------------|
| 1 | `boolean`                         | `true` if curl exited 0 and a status line could be parsed  |
| 2 | `Lib.Net.Curl.RawResponse\|string` | `{status, status_text, headers, body}` on success; an error string on failure |
| 3 | `vim.SystemCompleted`             | The raw `vim.system` result                                |

Each pair delivers these values to `cb` for the async form, or returns them
directly for the blocking form.
