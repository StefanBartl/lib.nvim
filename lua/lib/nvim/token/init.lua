---@module 'lib.nvim.token'
--- Ephemeral session-nonce / token generator, for handshake IDs, temp-window
--- IDs, correlation IDs, and similar internal bookkeeping.
---
--- NOT cryptographically secure — the seed mixes `hrtime()`, `math.random()`
--- and `os.clock()`, which is plenty of entropy to avoid accidental
--- collisions within a session but is trivially predictable to an attacker.
--- Do not use this for auth tokens, secrets, or anything security-critical.
---
--- Usage:
--- ```lua
--- local token = require("lib.nvim.token")
--- local id = token.gen_token()    -- 16 hex chars, e.g. "a1b2c3d4e5f60718"
--- local short_id = token.gen_token(8)
--- ```

require("lib.nvim.token.@types")

local uv = vim.uv or vim.loop

local M = {}

local HEX_CHARS = "0123456789abcdef"

---Fallback token: build a `len`-character hex string from raw random digits.
---@param len integer
---@return string
local function random_hex(len)
  local chars = {}
  for i = 1, len do
    local nibble = math.random(0, 15)
    chars[i] = HEX_CHARS:sub(nibble + 1, nibble + 1)
  end
  return table.concat(chars)
end

---Truncate or zero-pad `hex` to exactly `len` characters.
---@param hex string
---@param len integer
---@return string
local function fit_len(hex, len)
  if #hex >= len then
    return hex:sub(1, len)
  end
  return hex .. string.rep("0", len - #hex)
end

---Generate a non-cryptographic hex token, suitable for internal nonces/IDs.
---@param len? integer Desired length in hex characters (default `16`)
---@return string
function M.gen_token(len)
  len = len or 16

  local seed = table.concat({
    tostring(uv.hrtime()),
    tostring(math.random()),
    tostring(os.clock()),
  }, ":")

  local ok, hashed = false, nil
  if type(vim.fn.sha256) == "function" then
    ok, hashed = pcall(vim.fn.sha256, seed)
  end

  if ok and type(hashed) == "string" and #hashed > 0 then
    return fit_len(hashed, len)
  end

  return random_hex(len)
end

return M
