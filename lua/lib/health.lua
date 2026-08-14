---@module 'lib.health'
--- Health check for lib.nvim. Run with `:checkhealth lib`.

local M = {}

-- vim.health shim (start/ok/warn/error/info exist on all supported versions).
local H = vim.health or {}
local h_start = H.start or H.report_start
local h_ok = H.ok or H.report_ok
local h_warn = H.warn or H.report_warn
local h_error = H.error or H.report_error
local h_info = H.info or H.report_info

local MIN_NVIM = { 0, 10, 0 }

---@type string[] Repräsentative Module je Namespace (müssen ladbar sein).
local PROBE = {
  "lib.lua.tables.array",
  "lib.lua.strings",
  "lib.lua.functions.meta",
  "lib.nvim.notify",
  "lib.nvim.logger",
  "lib.nvim.progress",
  "lib.nvim.ui.kit",
  "lib.nvim.map",
  "lib.nvim.fs.is_dir",
  "lib.nvim.store.project",
  "lib.nvim.core",
  "lib.nvim.ui.kit",
  "lib.nvim.usercmd.composer",
  "lib.nvim.autocmd.dispatcher",
}

---@internal
---Checks whether the running Neovim version meets MIN_NVIM.
---@return boolean
local function version_ok()
  local v = vim.version()
  if v.major ~= MIN_NVIM[1] then
    return v.major > MIN_NVIM[1]
  end
  if v.minor ~= MIN_NVIM[2] then
    return v.minor > MIN_NVIM[2]
  end
  return v.patch >= MIN_NVIM[3]
end

---Runs all lib.nvim health checks and reports via vim.health.
function M.check()
  -- Neovim version --------------------------------------------------------
  h_start("lib.nvim: environment")
  local v = vim.version()
  local vstr = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if version_ok() then
    h_ok(("Neovim %s (>= %d.%d.%d)"):format(vstr, MIN_NVIM[1], MIN_NVIM[2], MIN_NVIM[3]))
  else
    h_warn(
      ("Neovim %s is older than the recommended %d.%d.%d"):format(
        vstr,
        MIN_NVIM[1],
        MIN_NVIM[2],
        MIN_NVIM[3]
      ),
      { "Some lib.nvim modules use vim.uv / vim.fs and may not work." }
    )
  end
  if vim.uv or vim.loop then
    h_ok("libuv bridge available (vim.uv)")
  else
    h_error("vim.uv / vim.loop missing")
  end

  -- Configuration ---------------------------------------------------------
  h_start("lib.nvim: configuration")
  local ok_cfg, cfg = pcall(require, "lib.config")
  if ok_cfg then
    local strat = cfg.get().strategy
    h_ok(("aggregator strategy: %q"):format(strat))
    h_info(('require("lib") -> %s'):format(cfg.strategy_module()))
  else
    h_error("lib.config failed to load: " .. tostring(cfg))
  end

  -- Module resolution -----------------------------------------------------
  h_start("lib.nvim: module resolution")
  local failed = 0
  for _, mod in ipairs(PROBE) do
    local ok, err = pcall(require, mod)
    if ok then
      h_ok(mod)
    else
      failed = failed + 1
      h_error(mod .. " failed to load", { tostring(err):gsub("\n.*", "") })
    end
  end
  if failed == 0 then
    h_ok(("all %d probed modules load"):format(#PROBE))
  end

  -- Aggregator surface ----------------------------------------------------
  h_start("lib.nvim: aggregator")
  local ok_lib, lib = pcall(require, "lib")
  if ok_lib then
    local ok_access = pcall(function()
      return lib.notify and lib.map and lib.is_windows
    end)
    if ok_access then
      h_ok('require("lib") resolves keys (notify, map, is_windows, …)')
    else
      h_warn('require("lib") loaded but key access failed')
    end
  else
    h_error('require("lib") failed: ' .. tostring(lib))
  end

  -- Active loggers --------------------------------------------------------
  -- Reports what each plugin registered via lib.nvim.logger.new(), so a bug
  -- report can name the log file to attach without the user having to know
  -- where it lives.
  h_start("lib.nvim: loggers")
  local ok_logger, logger = pcall(require, "lib.nvim.logger")
  if not ok_logger then
    h_error("lib.nvim.logger failed to load: " .. tostring(logger))
  elseif not logger.is_enabled() then
    h_warn("logging is globally disabled (logger.set_enabled(false))")
  else
    local loggers = logger.loggers()
    if #loggers == 0 then
      h_info("no loggers created yet (a plugin creates one on its first setup)")
    else
      for _, inst in ipairs(loggers) do
        h_info(
          ("%s — level %d, file: %s"):format(
            tostring(inst.name),
            tonumber(inst.level) or -1,
            inst.file or "disabled"
          )
        )
      end
    end
  end
end

return M
