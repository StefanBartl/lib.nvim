# `lib.nvim.contract.host`

The **persistent engine process**: a machine contract over a line protocol on
stdin and stdout. Moved here from `tasks_nvim.host` (tasks.nvim@921a0c4).

`nvim --headless -u NONE -l scripts/<plugin>-host.lua` does what a command line
`call <method>` does, many times in one process: the modules are loaded once and
a scan of a source that did not change can be answered from the plugin's caches,
so a question costs milliseconds and not a process start. Nothing else changes:
the answers are the documents of [`api.call`](../api/README.md), byte for byte.

```lua
-- <plugin>/host.lua
local api = require("<plugin>.api")                    -- a lib.nvim.contract.api instance
return require("lib.nvim.contract.host").make({
  api = api,
  call_opts = function() return { root = resolve_source() } end,   -- per request; or a table
})

-- scripts/<plugin>-host.lua: copy templates/contract_host.lua, replace MODULE and PLUGIN
-- (it finds lib.nvim, then calls require(MODULE).serve(io.stdin, io.stdout))
```

## The protocol

One line each way, UTF-8, `\t` separates the fields, a line ends with `\n`:

```
host   -> client   ready\t<PROTOCOL>
client -> host     <id>\t<method>\t<params>     id: digits, at most 15; params: the JSON of the request (empty: none), no line break in it
host   -> client   <id>\t<document>             the document api.call answers, on one line
```

- The host ends when its input ends, or when it cannot write its output any more
  (the client went away).
- A request is answered completely before the next is read: the plugin's lock is
  not re-entrant and the client keeps one question in flight.
- A line that is **not a request** (no id, an id of more than 15 digits, no
  method) is told on stderr and skipped: it has no id to answer with. An empty
  line is skipped silently.
- A line that is **too long** (`api.MAX_REQUEST_BYTES` plus 256) is skipped and
  told on stderr; when it starts with an id the client gets an error document
  (`payload_too_large`) for it, so it never waits for ever. (The original host
  skipped it without a word to the client.)
- A method or parameter the dispatcher does not accept is the dispatcher's own
  error document. If the dispatcher itself fails (it should not: `api.call` never
  raises) the answer is `{"code":"internal","message":"the host failed on this request",...}`.
- A non-flat method carries its parameters under `params`: the host wraps them
  (`{"params": <params>}`); a flat method (the write door,
  [`contract.ops`](../ops/README.md)) gets the text as it is. The text is
  spliced, not parsed: `{},"schema":9` as params adds a top-level field, which the
  dispatcher judges like any other. The client writes the whole line anyway.

## API

| | |
|---|---|
| `host.make{ api, protocol?, call_opts? }` | The host of one contract. `protocol`: the number after `ready` (default 1). `call_opts`: the options of every `api.call`, a table or a function asked per request. A wrong config raises where it is made. |
| `host.handle(line)` | One request line -> `<id>\t<document>`, or `nil` for a line that is no request. Never raises. |
| `host.serve(input, output, warn?)` | Serve until `input` ends. `input`/`output` need `read("l")`, `write`, `flush` (so a table works in a spec). `warn` defaults to stderr. |
| `host.PROTOCOL`, `host.max_line_bytes()` | The version and the longest line read, at call time. |

## Limit

A line is read whole before its length is judged (`file:read("l")`): a client
that sends an endless line without a line break holds memory until it stops. The
client is the app that started the host, and is trusted that far.

## The script

`templates/contract_host.lua` is the script to copy (see
[templates/README.md](../../../../../templates/README.md)). It must be a copy: it
runs before `lib.nvim` is on the runtimepath, so it cannot `require` anything of
it to find it. Exit codes: `0` when the input ended, `2` when `lib.nvim` is not found.
