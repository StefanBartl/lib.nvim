# `lib.nvim.token`

Ephemeral session-nonce / token generator, for handshake IDs, temp-window
IDs, correlation IDs, and similar internal bookkeeping. **Not
cryptographically secure** — do not use for auth tokens or secrets.

The seed mixes `(vim.uv or vim.loop).hrtime()`, `math.random()`, and
`os.clock()`, then hashes it with `vim.fn.sha256` when available, truncated
or zero-padded to the requested length. If `sha256` isn't available in the
running Neovim build, it falls back to a hex string built directly from
`math.random(0, 15)` digits.

## Usage

```lua
local token = require("lib.nvim.token")

local id = token.gen_token()      -- 16 hex chars, e.g. "a1b2c3d4e5f60718"
local short_id = token.gen_token(8)
```

## Returns

`gen_token(len?)` returns a single `string` — a `len`-character
(default `16`) lowercase hex string.
