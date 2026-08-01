---@module 'lib.nvim.telemetry.fingerprint'
--- Turns a call's arguments into a short, bounded, non-secret string key.
---
--- Deliberately NOT a serializer. Argument profiling exists to answer "do most
--- calls pass the same thing?", and that question is answerable from a shape
--- plus a truncated scalar. Storing the real values would mean writing file
--- paths, buffer contents and possibly tokens into `stdpath("cache")` — a
--- profiler that does that is a security bug wearing a feature's name.
---
--- Rules (see lua/lib/nvim/telemetry/README.md, "Argument profiling, done honestly"):
---   nil/boolean/number/short string -> the value itself
---   long string                     -> truncated with an ellipsis marker
---   table                           -> "<table:n=3>" (shape, not contents)
---   function/userdata/thread        -> "<function>" / "<userdata>" / "<thread>"

local M = {}

--- Longer than this and a string is truncated. 40 keeps a typical project path
--- recognizable ("/home/u/repos/lib.nvi…") while bounding the stored size.
local MAX_STRING = 40

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
    if #v <= MAX_STRING then
      return ("%q"):format(v)
    end
    return ("%q…"):format(v:sub(1, MAX_STRING))
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

M.MAX_STRING = MAX_STRING
M.MAX_ARGS = MAX_ARGS

return M
