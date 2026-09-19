---@module 'lib.nvim.telemetry.fingerprint'
--- Turns a call's arguments into a short, bounded, non-secret string key.
---
--- Deliberately NOT a serializer. Argument profiling exists to answer "do most
--- calls pass the same thing?", and that question is answerable from a shape
--- plus a digest. Storing the real values would mean writing file paths,
--- buffer contents and possibly tokens into `stdpath("cache")` — a profiler
--- that does that is a security bug wearing a feature's name.
---
--- Rules (see lua/lib/nvim/telemetry/README.md, "Argument profiling, done honestly"):
---   nil/boolean/number              -> the value itself
---   string                          -> "<string:len:digest>" (never the text)
---   table                           -> "<table:n=3>" (shape, not contents)
---   function/userdata/thread        -> "<function>" / "<userdata>" / "<thread>"

local bit = require("bit")

local M = {}

--- Only this many leading bytes go into a string's digest; a buffer's worth
--- of text would otherwise be hashed on every profiled call. Kept small and
--- close to the old (pre-SEC-13) 40-byte cap on purpose: this module is on
--- the hot path whenever telemetry is running (see
--- lib.nvim.telemetry.registry, which fingerprints every argument of every
--- wrapped call when a subscriber sets args=true), and "never store the
--- text" -- the property SEC-13 actually requires -- does not depend on how
--- many leading bytes get folded into the digest.
local DIGEST_BYTES = 64

---@internal
---32-bit FNV-1a over the first `DIGEST_BYTES` of `s`, as 8 hex digits. Not a
---security hash: it only has to keep equal inputs equal and unequal inputs
---mostly apart, without keeping the input.
---@param s string
---@return string
local function digest(s)
  local h = 2166136261
  for i = 1, math.min(#s, DIGEST_BYTES) do
    h = bit.bxor(h, s:byte(i))
    -- The FNV prime 16777619 is 2^24 + 403, split so no intermediate value
    -- leaves the range LuaJIT's bit operations accept.
    h = bit.tobit(bit.lshift(h, 24) + h * 403)
  end
  return bit.tohex(h, 8)
end

--- Beyond this many arguments the tail is summarized rather than described;
--- variadic call sites otherwise produce one distinct fingerprint per arity.
local MAX_ARGS = 4

---@param v any
---@return string
function M.value(v)
  local t = type(v)

  if v == nil then
    return "nil"
  elseif t == "boolean" or t == "number" then
    return tostring(v)
  elseif t == "string" then
    -- Never the text, at any length: a path, a buffer line or a token that
    -- happens to fit a size cap would otherwise be stored verbatim and end
    -- up in `stdpath("cache")`. Length plus a short digest still answers
    -- "do most calls pass the same thing?" without keeping the thing.
    return ("<string:%d:%s>"):format(#v, digest(v))
  elseif t == "table" then
    -- Shape only. `#v` is cheap; a full pair count on a large table is not,
    -- and this runs on every profiled call.
    local n = #v
    if n > 0 then
      return ("<table:#%d>"):format(n)
    end
    return next(v) == nil and "<table:empty>" or "<table:map>"
  end

  return ("<%s>"):format(t)
end

---Fingerprint a whole argument list.
---@param n integer  # result of select("#", ...) at the call site
---@param ... any
---@return string
function M.of(n, ...)
  if n == 0 then
    return "()"
  end

  local parts = {}
  local shown = n < MAX_ARGS and n or MAX_ARGS
  for i = 1, shown do
    parts[i] = M.value((select(i, ...)))
  end
  if n > shown then
    parts[shown + 1] = ("…+%d"):format(n - shown)
  end

  return "(" .. table.concat(parts, ", ") .. ")"
end

M.DIGEST_BYTES = DIGEST_BYTES
M.MAX_ARGS = MAX_ARGS

return M
