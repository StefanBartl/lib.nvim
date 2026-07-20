---@module 'lib.nvim.normalize.utils'

local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}


--- Trim leading/trailing ASCII whitespace.
---@param s any
---@return string
function M.trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Clamp number into [min,max] (inclusive); nil min/max are ignored.
---@param n number
---@param min number|nil
---@param max number|nil
---@return number
function M.clamp(n, min, max)
  if min and n < min then
    n = min
  end
  if max and n > max then
    n = max
  end
  return n
end

--- Coalesce: return the first non-nil argument.
---@generic T
---@param ... T?
---@return T|nil
function M.coalesce(...)
  local args = { ... }
  for i = 1, #args do
    if args[i] ~= nil then
      return args[i]
    end
  end
  return nil
end

--- Deduplicate a string list while preserving order.
---@param list Lib.Normalize.StringList
---@return Lib.Normalize.StringList
function M.dedup_strings(list)
  local seen = {} ---@type table<string, boolean>
  local out = {} ---@type Lib.Normalize.StringList
  for i = 1, #list do
    local v = list[i]
    if type(v) == "string" then
      if not seen[v] then
        seen[v] = true
        out[#out + 1] = v
      end
    end
  end
  return out
end

--- Normalize a filesystem path using Neovim facilities if present.
--- Expansion of `~`, `$VAR`, `${VAR}` and `%VAR%` is delegated to
--- `lib.nvim.cross.fs.expand_path` first (the only one of the two that
--- understands `%VAR%`), then `vim.fs.normalize` handles separator/`.`/`..`
--- normalization with its own env expansion disabled to avoid doing that
--- work twice.
---@param p any
---@return string
function M.normalize_path(p)
  if type(p) ~= "string" or p == "" then
    return ""
  end
  local expanded = expand_path(p)
  if vim and vim.fs and vim.fs.normalize then
    return vim.fs.normalize(expanded, { expand_env = false })
  end
  -- Fallback: collapse consecutive slashes and strip trailing slash (except root)
  local s = expanded:gsub("[/\\]+", "/")
  if #s > 1 and s:sub(-1) == "/" then
    s = s:sub(1, -2)
  end
  return s
end

--- Return "file", "directory" or "" (does not exist) if libuv is available.
---@param p string
---@return string
function M.path_kind(p)
  local uv = vim and (vim.uv or vim.loop) or nil
  if not uv or p == "" then
    return ""
  end
  local st = uv.fs_stat(p)
  return (st and st.type) or ""
end

---@type Lib.Normalize.Utils
return M
