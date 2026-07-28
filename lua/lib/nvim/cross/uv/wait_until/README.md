# `lib.nvim.cross.uv.wait_until`

Polls a predicate on a libuv timer until it returns `true` or a maximum
attempt count is reached. Generic — not tied to any specific filesystem or
process use case (e.g. "wait for a file to appear", "wait for a port to
open" are both just callers of this).

## Usage

```lua
local wait_until = require("lib.nvim.cross.uv.wait_until")

wait_until(function()
  return vim.fn.filereadable("/tmp/ready") == 1
end, { interval_ms = 50, max_attempts = 20 }, function(ok)
  if ok then
    print("file appeared")
  else
    print("gave up waiting")
  end
end)
```

`opts` is optional: `{ interval_ms?, max_attempts? }`, defaulting to
`interval_ms = 100`, `max_attempts = 50`. The predicate is checked
immediately on the first timer tick (timer starts with `0` initial delay,
then fires every `interval_ms`), so a predicate that's already true resolves
almost immediately rather than waiting a full interval first. `cb(ok)` is
always dispatched via `vim.schedule`.
