# `lib.nvim.net.curl`

Async (and blocking) HTTP-via-curl helper — the shared core behind every
plugin that hand-rolls curl-argv-building plus `vim.system`. Three tiers:
`fetch_json`/`fetch_json_blocking` decode the response body as JSON for you;
`fetch_raw`/`fetch_raw_blocking` return the response verbatim — status,
headers and body, undecoded — for a caller that needs to *show* the
response, or one whose content type is not JSON at all; `download`/
`download_blocking` write the body straight to a file instead of buffering
it in memory.

Builds a curl argv from `opts` (method, headers, bearer token, query string,
body, multipart form fields, basic auth, proxy, HTTP version, raw
passthrough args), spawns it through `vim.system` (Neovim 0.10+ required —
no `jobstart` fallback).

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

-- Download tier, blocking — body written straight to a file
local ok3, resp3 = curl.download_blocking("https://example.com/big.zip", "/tmp/big.zip")
if ok3 then
  print(resp3.status)   -- resp3.body is "" -- the body went to /tmp/big.zip
end

-- Basic auth, multipart form, proxy, forced HTTP/2, raw passthrough
curl.fetch_json_blocking("https://api.example.com/upload", {
  method = "POST",
  auth = { user = "alice", pass = "hunter2" },
  form = { name = "report", file = "@/tmp/report.pdf" },
  proxy = "http://proxy.local:8080",
  http_version = "2",
  raw_args = { "--compressed" },
})
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

**`download` / `download_blocking`**

Same shape as `fetch_raw`/`fetch_raw_blocking` — `response.body` is always
`""`, since the body was written to `dest_path` instead of stdout.

Each pair delivers these values to `cb` for the async form, or returns them
directly for the blocking form.

## `opts` fields (all tiers)

| Field          | Sent as                              | Notes                                                    |
|-----------------|----------------------------------------|-------------------------------------------------------------|
| `method`        | `-X <method>`                          | Default `"GET"`                                              |
| `headers`       | `-H "k: v"` per entry                  |                                                                |
| `bearer_token`  | `-H "Authorization: Bearer <token>"`   |                                                                |
| `query`         | `?k=v&...` appended to the URL         | URL-encoded                                                   |
| `body`          | `-d <body>`                            | Raw request body                                              |
| `auth`          | `-u user:pass`                         | `{ user, pass }`                                              |
| `form`          | `-F "k=v"` per entry                   | A value starting with `@` is curl's own file-upload syntax   |
| `raw_args`      | appended verbatim                      | Escape hatch for anything not otherwise covered              |
| `http_version`  | `--http1.0` / `--http1.1` / `--http2`  | `"1.0"`, `"1.1"`, or `"2"`                                    |
| `proxy`         | `-x <proxy>`                           |                                                                |
| `insecure`      | `-k`                                   | Skip TLS certificate verification                             |
| `timeout_ms`    | `vim.system`'s `timeout`/`wait(timeout)` |                                                              |
