---@module 'lib.lua.uuid'
--- UUIDv4 generation and formatting helpers, pure Lua (no `vim.*`).
---
--- Uses `math.random`, seeded once at module load time. This is NOT
--- cryptographically secure — it only provides enough entropy for typical
--- UI/temp-id use (list keys, scratch buffer names, request ids for
--- logging, …). Do not use these ids for security-sensitive purposes
--- (tokens, session ids, anything an attacker could predict or must not
--- collide against adversarial input).

math.randomseed(os.time() + math.floor(os.clock() * 1000000))

---@type LibUuid
local M = {}

local HEX = "0123456789abcdef"
local VARIANT_CHARS = { "8", "9", "a", "b" }

---Return `n` random lowercase hex digits concatenated.
---@param n integer
---@return string
local function rand_hex(n)
  local out = {}
  for i = 1, n do
    local idx = math.random(1, #HEX)
    out[i] = HEX:sub(idx, idx)
  end
  return table.concat(out)
end

---Generate a random UUIDv4 string.
---
---Format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`, where the version nibble
---is fixed to `4` and the variant nibble is one of `8`, `9`, `a`, `b`, per
---RFC 4122 section 4.4.
---@nodiscard
---@return string uuid Lowercase, hyphenated UUIDv4
function M.generate()
  local variant = VARIANT_CHARS[math.random(1, #VARIANT_CHARS)]

  return string.format(
    "%s-%s-4%s-%s%s-%s",
    rand_hex(8),
    rand_hex(4),
    rand_hex(3),
    variant,
    rand_hex(3),
    rand_hex(12)
  )
end

---Transform a UUID string's presentation. Does not validate `uuid`'s shape
---beyond `type(uuid) == "string"`.
---@nodiscard
---@param uuid string
---@param style? "compact"|"upper"|"braced" Defaults to passthrough for an unrecognized/nil style
---@return string
function M.format(uuid, style)
  if type(uuid) ~= "string" then
    return uuid
  end

  if style == "compact" then
    return (uuid:gsub("%-", ""))
  elseif style == "upper" then
    return uuid:upper()
  elseif style == "braced" then
    return "{" .. uuid .. "}"
  end

  return uuid
end

---Convenience: generate a UUIDv4 and format it in one call.
---@nodiscard
---@param style? "compact"|"upper"|"braced"
---@return string
function M.get(style)
  return M.format(M.generate(), style)
end

return M
