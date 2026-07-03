---@module 'lib.nvim.system.env'
--- Computed, memoized snapshot of the host environment.
---
--- This is the library-side home of what used to be a per-config `system.env`
--- module: a single table describing OS, shell and a couple of well-known paths.
--- Platform booleans are delegated to `lib.nvim.cross.platform` so detection
--- logic lives in exactly one place.
---
--- Pure by default — `get()` only reads and caches; nothing global is touched.
--- Publishing the snapshot to `vim.g.*` is opt-in via `publish_globals()` (or the
--- `publish_globals` flag of `require("lib.nvim.system").setup`).
---
---   local env = require("lib.nvim.system.env").get()
---   if env.is_windows then ... end
---
--- Note on WSL: unlike a naive `not win and not mac` definition, the platform
--- booleans here are mutually exclusive. On WSL `is_wsl == true` and
--- `is_linux == false`.

local M = {}

--- Default set of fields published to `vim.g` by `publish_globals()`.
--- `pathsep`/`home` are intentionally excluded: they collide with nothing useful
--- as globals and are better read from the snapshot.
local DEFAULT_GLOBAL_FIELDS = {
  "is_windows",
  "is_wsl",
  "is_linux",
  "is_macos",
  "is_pwsh",
  "repo_base",
}

---@type Lib.System.Env|nil
local cache

---@return Lib.System.Env
local function compute()
  local is_windows = require("lib.nvim.cross.platform.is_windows")()

  return {
    is_windows = is_windows,
    is_wsl = require("lib.nvim.cross.platform.is_wsl")(),
    is_macos = require("lib.nvim.cross.platform.is_macos")(),
    is_linux = require("lib.nvim.cross.platform.is_linux")(),
    is_pwsh = vim.fn.executable("pwsh") == 1,
    repo_base = vim.env.REPOS_DIR,
    pathsep = is_windows and "\\" or "/",
    home = vim.fn.expand("~"),
  }
end

--- Return the cached environment snapshot, computing it once on first call.
---@param opts? { refresh?: boolean } # `refresh = true` recomputes the snapshot.
---@return Lib.System.Env
function M.get(opts)
  if opts and opts.refresh then
    cache = nil
  end
  if not cache then
    cache = compute()
  end
  return cache
end

--- Publish selected snapshot fields to `vim.g.<field>`.
--- Opt-in side effect: mirrors the legacy `system.env` behavior for configs that
--- read `vim.g.is_windows` & friends (e.g. from Vimscript or plugin specs).
---@param opts? { fields?: string[] } # Field names to publish; defaults to the platform/shell/repo set.
---@return Lib.System.Env
function M.publish_globals(opts)
  local env = M.get()
  local fields = (opts and opts.fields) or DEFAULT_GLOBAL_FIELDS
  for _, name in ipairs(fields) do
    vim.g[name] = env[name]
  end
  return env
end

return M
