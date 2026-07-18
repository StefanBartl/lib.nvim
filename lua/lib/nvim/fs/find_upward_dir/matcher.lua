---@module 'lib.nvim.fs.find_upward_dir.matcher'
--- Marker-name matching shared by `find_upward_dir` and `find_root`.
---
--- Markers are plain basenames (`.git`, `package.json`) or shell-style globs
--- (`*.rockspec`, `*.cabal`). Globs are what `vim.fs.find`'s name-list form
--- cannot express — it compares names verbatim — so a marker set containing
--- one has to be turned into a predicate instead.
---
--- Only `*` and `?` are supported; that covers every root marker seen in the
--- wild and keeps the translation to a Lua pattern trivial and total.

local M = {}

---True when any marker uses glob syntax.
---@param names string[]
---@return boolean
function M.has_glob(names)
  for _, name in ipairs(names) do
    if name:find("[%*%?]") then
      return true
    end
  end
  return false
end

---Translate a single glob into an anchored Lua pattern.
---@param glob string
---@return string
local function to_pattern(glob)
  -- Escape every Lua-pattern magic character, then re-open the two wildcards.
  local escaped = glob:gsub("[%^%$%(%)%%%.%[%]%+%-%*%?]", "%%%0")
  escaped = escaped:gsub("%%%*", ".*"):gsub("%%%?", ".")
  return "^" .. escaped .. "$"
end

---Build a predicate matching any of `names`, glob-aware.
---
---The returned function has the signature `vim.fs.find` expects for its
---predicate form: `fun(name: string, path: string): boolean`.
---@param names string[]
---@return fun(name: string, path?: string): boolean
function M.build(names)
  local exact = {}
  local patterns = {}

  for _, name in ipairs(names) do
    if name:find("[%*%?]") then
      patterns[#patterns + 1] = to_pattern(name)
    else
      exact[name] = true
    end
  end

  return function(name)
    if exact[name] then
      return true
    end
    for _, pattern in ipairs(patterns) do
      if name:match(pattern) then
        return true
      end
    end
    return false
  end
end

return M
