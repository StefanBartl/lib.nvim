---@module 'lib.nvim.fs.path_shorten'
-- Utility module to shorten file paths for use in Telescope and fzf-lua.
-- The algorithm preserves the path start (drive/root) and the filename at the end,
-- and replaces a variable-length middle section with an ellipsis ("…") until the
-- resulting string fits the requested maximum length.

--- Determine path separator depending on platform.
--- @return string separator ("/" on POSIX, "\" on Windows)
local function get_sep()
  -- package.config:sub(1,1) returns the directory separator for the current Lua build
  return package.config:sub(1, 1)
end

--- Split a string by a separator.
--- Keeps a leading empty token to denote a leading separator (root) if present.
--- @param s string
--- @param sep string
--- @return string[] parts
local function split(s, sep)
  ---@type string[]
  local parts = {}
  if sep == "\\" then
    -- escape backslash for pattern
    sep = "\\\\"
  end
  local pattern = "([^" .. sep .. "]+)"
  for part in s:gmatch(pattern) do
    parts[#parts + 1] = part
  end
  -- If original string starts with separator, represent root by inserting empty first element.
  if s:sub(1, 1) == get_sep() then
    table.insert(parts, 1, "")
  end
  return parts
end

--- Join parts into a path using separator.
--- If first part is empty string, it denotes a leading separator (root).
--- @param parts string[]
--- @param sep string
--- @return string
local function join(parts, sep)
  if #parts == 0 then
    return ""
  end
  if parts[1] == "" then
    if #parts == 1 then
      return sep
    end
    -- table.unpack compatibility: use table.unpack (Lua 5.2+) or unpack as fallback
    ---@diagnostic disable-next-line: deprecated
    local unpack = table.unpack or unpack
    return sep .. table.concat({ unpack(parts, 2) }, sep)
  end
  return table.concat(parts, sep)
end

--- Return length in characters (tries utf8.len, falls back to byte length).
--- @param s string
--- @return integer
local function strlen(s)
  return #s
end

--- Shorten a path so that it fits within max_len characters.
--- Preserves the first meaningful segment (drive or root marker) and the last segment (filename).
--- Collapses middle segments by replacing them with an ellipsis ("…") and progressively
--- reduces kept segments until the result fits.
--- @param path string full path to shorten
--- @param max_len integer maximum allowed length (characters, >=1)
--- @return string shortened path (never longer than max_len if max_len >= 1)
return function(path, max_len)
  if type(path) ~= "string" then
    return path
  end
  if type(max_len) ~= "number" or max_len < 1 then
    return path
  end

  local sep = get_sep()
  local ell = "…"

  -- fast path: already fits
  if strlen(path) <= max_len then
    return path
  end

  local parts = split(path, sep) ---@type string[]
  local n = #parts

  if n == 0 then
    if strlen(path) <= max_len then
      return path
    else
      return ell .. path:sub(-math.max(1, max_len - 1))
    end
  end

  local has_root = parts[1] == ""

  -- Determine first_display (drive or first non-empty part). For Windows absolute like "C:\"
  local first_part = parts[1]
  if has_root then
    if sep == "/" then
      first_part = sep -- always show leading '/' for POSIX absolute paths
    else
      first_part = parts[1] -- for Windows, keep "C:" visible
    end
  end

  local last_part = parts[n]

  -- If even "first + sep + last" does not fit, then show ellipsis + truncated filename (right-aligned)
  local min_needed = strlen(first_part) + strlen(sep) + strlen(last_part)
  if min_needed > max_len then
    local allowed_for_last = math.max(1, max_len - strlen(ell))
    local last_visible = last_part
    if strlen(last_part) > allowed_for_last then
      -- truncate from left to keep the filename end visible (byte-based)
      last_visible = last_part:sub(-allowed_for_last)
    end
    return ell .. last_visible
  end

  -- 1) Try collapsing entire middle to ellipsis: first + sep + ell + sep + last
  local function build_with_ellipsis()
    local out_parts = {}
    if has_root then
      table.insert(out_parts, "") -- leading '/' will be produced by join
    else
      table.insert(out_parts, parts[1])
    end
    -- only add ellipsis if there are more than 2 segments besides root
    if n > 2 then
      table.insert(out_parts, ell)
    end
    table.insert(out_parts, parts[n])
    return join(out_parts, sep)
  end

  local attempt = build_with_ellipsis()
  if strlen(attempt) <= max_len then
    return attempt
  end

  -- 2) Try keeping increasing number of trailing segments (right-most) with a leading ellipsis
  for k = 1, n - 1 do
    local keep_from = n - k + 1
    local out_parts = {}
    if has_root then
      table.insert(out_parts, "") -- leading '/' always visible
    else
      table.insert(out_parts, parts[1])
    end
    -- only add ellipsis if there are collapsed segments between root/first and last segments
    if keep_from > (has_root and 2 or 1) then
      table.insert(out_parts, ell)
    end
    for i = keep_from, n do
      table.insert(out_parts, parts[i])
    end
    local cand = join(out_parts, sep)
    if strlen(cand) <= max_len then
      return cand
    end
  end

  -- 3) Last resort: show ellipsis + as much of the rightmost characters as fits
  local allowed = max_len - strlen(ell)
  if allowed <= 0 then
    return ell
  end
  local tail = path:sub(-allowed)
  return ell .. tail
end
