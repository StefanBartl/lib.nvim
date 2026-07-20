---@module 'lib.nvim.fs.is_subpath.alternative'
--- Utility helpers for path normalization and membership checks.
--- Provides `norm` to canonicalize paths and `is_subpath` to test whether
--- a candidate path is the same as or contained inside a base path.
--- Normalization resolves "." and ".." segments, collapses repeated separators,
--- and normalizes Windows backslashes to the platform separator.
---
--- Note: This module performs textual normalization and does not query the filesystem
--- (no symlink resolution). For symlink-aware checks, one must use OS-specific APIs.

local M = {}

--- Return platform path separator ("/" on POSIX, "\" on Windows).
--- @return string
local function sep()
  -- package.config:sub(1,1) documents the directory separator for this platform.
  return package.config:sub(1, 1) or "/"
end

--- Split a string by a single-character separator.
--- @param s string
--- @param delimiter string
--- @return string[] parts
local function split(s, delimiter)
  local parts = {}
  if s == nil or s == "" then
    return parts
  end
  local pattern = "([^" .. delimiter .. "]+)"
  for part in s:gmatch(pattern) do
    parts[#parts + 1] = part
  end
  return parts
end

--- Join path components with platform separator.
--- @param parts string[]
--- @return string
local function join(parts)
  local joined = table.concat(parts, sep())
  -- If first part is empty string, it means an absolute path starting with sep
  if #parts > 0 and parts[1] == "" then
    return sep() .. joined:sub(2) -- avoid double sep
  end
  return joined
end

--- Normalize a path string:
--- - Replace backslashes with platform separator on Windows.
--- - Collapse consecutive separators.
--- - Resolve "." and ".." segments (textually, without resolving symlinks).
--- - Remove trailing separator except for root ("/" or "C:\").
--- @param p string
--- @return string normalized_path
local function norm(p)
  if type(p) ~= "string" then
    return ""
  end

  local s = sep()

  -- 1) Normalize slashes: convert both kinds to the platform separator
  if s == "\\" then
    -- On Windows, convert forward slashes to backslashes
    p = p:gsub("/", "\\")
  else
    -- On POSIX, convert backslashes to forward slashes (rare)
    p = p:gsub("\\", "/")
  end

  -- 2) Collapse multiple consecutive separators into one
  local pat = s .. s .. "+"
  p = p:gsub(pat, s)

  -- 3) Detect absolute path prefix (e.g., leading "/" or "C:\")
  local is_abs = false
  local drive_prefix = nil
  if s == "\\" then
    -- Windows: handle "C:\..." or UNC paths like "\\server\share"
    local m_drive = p:match("^([A-Za-z]:)\\")
    if m_drive then
      is_abs = true
      drive_prefix = m_drive
      -- remove drive prefix from p for component processing
      p = p:sub(#m_drive + 2) -- skip "C:\"
    elseif p:sub(1, 2) == "\\\\" then
      -- UNC path: treat leading double backslash as absolute marker and keep it
      is_abs = true
      drive_prefix = "\\\\"
      p = p:sub(3)
    elseif p:sub(1, 1) == "\\" then
      -- Leading single backslash - treat as absolute-ish
      is_abs = true
      p = p:sub(2)
    end
  else
    if p:sub(1, 1) == "/" then
      is_abs = true
      p = p:sub(2)
    end
  end

  -- 4) Split into components and process "." and ".."
  local parts = split(p, s)
  local stack = {}
  for i = 1, #parts do
    local part = parts[i]
    if part == "" or part == "." then
      -- skip
    elseif part == ".." then
      if #stack > 0 then
        -- pop last component
        table.remove(stack)
      else
        -- if absolute path, ignore attempts to go above root; for relative, keep ".."
        if not is_abs then
          stack[#stack + 1] = ".."
        end
      end
    else
      stack[#stack + 1] = part
    end
  end

  -- 5) Rebuild path
  local result = join(stack)

  if is_abs then
    if s == "\\" then
      if drive_prefix then
        -- Reattach drive or UNC prefix.
        if drive_prefix == "\\\\" then
          result = "\\\\" .. (result == "" and "" or result)
        else
          result = drive_prefix .. "\\" .. result
        end
      else
        result = "\\" .. result
      end
    else
      result = "/" .. result
    end
  end

  -- 6) Remove trailing separator (unless result is root like "/" or "C:\")
  if result ~= "" then
    if s == "\\" then
      -- Windows root detection: "X:\" or "\\server\share"
      if not result:match("^%a:$") and not result:match("^%a:\\$") and not result:match("^\\\\") then
        if result:sub(-1) == "\\" then
          result = result:sub(1, -2)
        end
      end
    else
      if result ~= "/" and result:sub(-1) == "/" then
        result = result:sub(1, -2)
      end
    end
  end

  return (result == "" and "." or result)
end

--- Public normalized function exposed
--- @param p string
--- @return string
function M.norm(p)
  return norm(p)
end

--- Check whether `path` is equal to or contained within `base`.
--- Both inputs are normalized before comparison. The check is textual
--- and does not resolve symlinks. Examples:
--- - is_subpath("/a/b/c", "/a/b") -> true
--- - is_subpath("/a/b", "/a/b")     -> true
--- - is_subpath("/a/bc", "/a/b")    -> false
--- - is_subpath("a/b/c", "a/b")     -> true
--- @param path string Candidate path to test.
--- @param base string Base directory to test against.
--- @return boolean true if `path` is same as or inside `base`.
local function is_subpath(path, base)
  path = norm(path)
  base = norm(base)

  -- If exactly equal, treat as subpath (same directory)
  if path == base then
    return true
  end

  -- If path shorter or equal length (already handled equal), cannot be inside base
  if #path <= #base then
    return false
  end

  -- Ensure base ends with separator so prefix match requires full directory name.
  local s = sep()
  if base:sub(-1) ~= s then
    base = base .. s
  end

  -- Quick prefix check
  return path:sub(1, #base) == base
end

--- Expose function
--- @param path string
--- @param base string
--- @return boolean
function M.is_subpath(path, base)
  return is_subpath(path, base)
end

-- Simple inline tests (run by requiring the module interactively)
-- They are comments and not executed automatically; users can uncomment to test.
--[[
local tests = {
  { "/foo/bar/baz", "/foo/bar", true },
  { "/foo/bar", "/foo/bar", true },
  { "/foo/barbaz", "/foo/bar", false },
  { "foo/bar/baz", "foo/bar", true },
  { "/foo/../foo/bar", "/foo/bar", true },
  { "C:\\proj\\src\\mod", "C:\\proj\\src", true },
  { "C:\\proj\\src\\..\\other", "C:\\proj\\other", true },
}
for _, t in ipairs(tests) do
  local ok = is_subpath(t[1], t[2]) == t[3]
  print(string.format("test %s | %s in %s -> %s", ok and "OK" or "FAIL", t[1], t[2], tostring(is_subpath(t[1], t[2]))))
end
]]

return M
