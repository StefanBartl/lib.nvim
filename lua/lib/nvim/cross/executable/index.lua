---@module 'lib.nvim.cross.executable.index'
--- One-shot index of the executables on $PATH, for native Windows.
---
--- `vim.fn.exepath()` / `vim.fn.executable()` resolve one name by walking every
--- $PATH entry and, for a bare name, trying every $PATHEXT extension in each:
--- with 72 entries and 11 extensions that is ~790 `stat` calls for a name that
--- is NOT installed, ~40 ms measured on Windows (each stat also passes the AV
--- filter driver). A config that asks for a dozen missing tools -- dap adapters,
--- formatters, language servers -- pays that dozen times over.
---
--- The index reads every $PATH directory once (`fs_scandir`, ~65 ms for ~7300
--- entries) and answers every later lookup from a table, in microseconds.
---
--- What it reproduces from Vim's own lookup on Windows (verified against
--- `vim.fn.exepath`/`executable`, including the quirks):
---   * $PATH order decides between two directories,
---   * inside one directory an EXACT file name wins over a $PATHEXT expansion,
---     and any existing file counts, whatever its extension (`npm`, the shell
---     script next to `npm.cmd`, resolves to `npm`, and `x.txt` is "executable"),
---   * otherwise the bare name (`git`) tries the $PATHEXT extensions in order
---     (`x.com` before `x.exe`),
---   * matching is case-insensitive.
--- What it deliberately does not: the current directory is not searched first.
---
--- It is an *answer with an expiry*, never a source of truth -- `lookup()`
--- answers "unknown" (and the caller falls back to `vim.fn`) when the index is
--- absent, when $PATH or $PATHEXT changed since it was built (mason prepends
--- its bin dir mid-session), or when it is older than `MAX_AGE_MS` (a tool
--- installed into a $PATH directory during the session must show up sooner or
--- later). Only native Windows uses it: on other systems $PATH is short and
--- there is no $PATHEXT multiplier, so `vim.fn.exepath` is already cheap.
---
--- Building is cheap enough to do synchronously in tests and is done in the
--- background otherwise (`build_async`: one directory per event-loop tick, so
--- no single slice blocks for longer than one `fs_scandir`).

local uv = vim.uv or vim.loop

local M = {}

--- Expire an index after this long; a stale one answers "unknown".
M.MAX_AGE_MS = 60000

local DEFAULT_EXTS = ".COM;.EXE;.BAT;.CMD"

---@class Lib.Cross.Executable.IndexState
---@field map table<string, string>|nil  lower-case name -> absolute path
---@field key string|nil                 PATH + PATHEXT the index was built from
---@field built_at number|nil            ms (uv.hrtime based)
---@field building boolean

---@type Lib.Cross.Executable.IndexState
local state = { map = nil, key = nil, built_at = nil, building = false }

---@return number ms
local function now_ms()
  return uv.hrtime() / 1e6
end

---@return boolean
function M.supported()
  return require("lib.nvim.cross.platform.is_windows")()
end

---The two strings the index depends on, as one comparable key.
---@return string
local function current_key()
  return (vim.env.PATH or "") .. "\0" .. (vim.env.PATHEXT or "")
end

---$PATH entries in order, without empty ones.
---@return string[]
local function path_dirs()
  return vim.split(vim.env.PATH or "", ";", { plain = true, trimempty = true })
end

---$PATHEXT as lower-case extensions in order (`.exe`), default when unset.
---@return string[]
local function path_exts()
  local raw = vim.env.PATHEXT
  if not raw or raw == "" then
    raw = DEFAULT_EXTS
  end
  local out = {}
  for ext in raw:gmatch("[^;]+") do
    out[#out + 1] = ext:lower()
  end
  return out
end

---Read one directory into `map`, first directory wins. Inside the directory an
---exact file name beats an expansion, and the $PATHEXT rank decides which of
---`x.com`/`x.exe` answers for the bare name `x`.
---@param map table<string, string>
---@param dir string
---@param rank table<string, integer>  extension -> position in $PATHEXT
local function scan_dir(map, dir, rank)
  local handle = uv.fs_scandir(dir)
  if not handle then
    return
  end
  ---@type table<string, { rank: integer, path: string }>
  local bare = {}
  ---@type table<string, string>
  local full = {}
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind ~= "directory" then
      local lower = name:lower()
      local path = dir .. "\\" .. name
      full[lower] = path
      local ext = lower:match("(%.[^%.]+)$")
      local r = ext and rank[ext]
      if r then
        local base = lower:sub(1, #lower - #ext)
        local best = bare[base]
        if not best or r < best.rank then
          bare[base] = { rank = r, path = path }
        end
      end
    end
  end
  -- Per directory the exact name is tried first, then the expansions; the
  -- first directory that has either one answers.
  for name, path in pairs(full) do
    if map[name] == nil then
      map[name] = path
    end
  end
  for name, best in pairs(bare) do
    if map[name] == nil and full[name] == nil then
      map[name] = best.path
    end
  end
end

---@param exts string[]
---@return table<string, integer>
local function ext_rank(exts)
  local rank = {}
  for i, ext in ipairs(exts) do
    rank[ext] = rank[ext] or i
  end
  return rank
end

---Index a list of directories. Pure with respect to the environment (takes the
---directories and extensions as arguments), so it is what the tests exercise.
---@param dirs string[]
---@param exts string[]  lower-case, with the dot
---@return table<string, string>
function M.scan(dirs, exts)
  local map, seen, rank = {}, {}, ext_rank(exts)
  for _, dir in ipairs(dirs) do
    local trimmed = dir:gsub("[/\\]+$", "")
    local id = trimmed:lower()
    if trimmed ~= "" and not seen[id] then
      seen[id] = true
      scan_dir(map, trimmed, rank)
    end
  end
  return map
end

---@return boolean
function M.ready()
  return state.map ~= nil
    and state.key == current_key()
    and now_ms() - (state.built_at or 0) <= M.MAX_AGE_MS
end

---@return boolean
function M.building()
  return state.building
end

---Answer from the index.
---@param name string
---@return string|nil path   the resolved path, nil when not on $PATH
---@return boolean known     false: the index cannot answer, ask `vim.fn`
function M.lookup(name)
  if not M.supported() then
    return nil, false
  end
  -- A path (`C:\tools\x`, `./x`) is not a PATH search.
  if type(name) ~= "string" or name == "" or name:find("[/\\]") then
    return nil, false
  end
  if not M.ready() then
    return nil, false
  end
  return state.map[name:lower()], true
end

---Build the index now, blocking. ~65 ms with a 72-entry $PATH.
---@return nil
function M.build()
  local key = current_key()
  state.map = M.scan(path_dirs(), path_exts())
  state.key = key
  state.built_at = now_ms()
end

---Build the index in the background, one directory per event-loop tick. A
---no-op while one is being built. The result is dropped when $PATH/$PATHEXT
---changed meanwhile: an index of a $PATH that is gone would answer wrongly.
---@param on_done? fun()
---@return nil
function M.build_async(on_done)
  if state.building or not M.supported() then
    return
  end
  state.building = true

  local key = current_key()
  local dirs, rank = path_dirs(), ext_rank(path_exts())
  local map, seen, i = {}, {}, 0

  local function step()
    i = i + 1
    local dir = dirs[i]
    if not dir then
      state.building = false
      if key == current_key() then
        state.map, state.key, state.built_at = map, key, now_ms()
        if on_done then
          on_done()
        end
      end
      return
    end
    local trimmed = dir:gsub("[/\\]+$", "")
    local id = trimmed:lower()
    if trimmed ~= "" and not seen[id] then
      seen[id] = true
      pcall(scan_dir, map, trimmed, rank)
    end
    vim.schedule(step)
  end

  vim.schedule(step)
end

---Forget the index (and abandon nothing that is running: a build that finishes
---afterwards simply publishes a fresh one).
---@return nil
function M.reset()
  state.map, state.key, state.built_at = nil, nil, nil
end

return M
