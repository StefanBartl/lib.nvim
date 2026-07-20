---@module 'lib.nvim.require'
---Safe and extended require utilities

local notify = require("lib.nvim.notify").create("[lib.nvim.require]")

local M = {}

---Safe require with structured error handling
---@param name string Module name
---@return boolean ok Success flag
---@return any result Module or error message
function M.safe(name)
  if type(name) ~= "string" then
    return false, "invalid module name"
  end

  local ok, mod = pcall(require, name)
  if not ok then
    return false, mod
  end
  return true, mod
end

---Load all modules in a directory
---@param dir string Directory relative to lua/
---@param calls? string|string[]|"" Functions to call on loaded modules
---@return nil
function M.dir(dir, calls)
--[[
This utility loads all Lua modules located directly inside a given directory
under `lua/<dir>` and optionally invokes well-defined lifecycle functions
on each loaded module.

Key features:

1. Directory-based module loading
   All `*.lua` files inside `lua/<dir>` are required non-recursively.
   The module name is derived as `<dir>.<filename_without_extension>`.

2. Self-skip protection
   The module that calls `require_dir` is automatically skipped.
   This prevents infinite recursion in setups like:
     lua/lib/func.lua  -> require_dir("lib")
   where `lib.func` would otherwise re-require itself.

3. Optional function dispatch
   A second argument controls which functions are invoked on each module:
     - nil:
         Calls `setup({})` if present (default behavior).
     - string:
         Calls exactly that function name, e.g. "apply".
     - string[]:
         Calls all listed function names in order.
     - empty string (""):
         Calls nothing at all; modules are only required.

   Only functions that exist and are callable are invoked.
   Errors during require or function execution are reported via `vim.notify`.

4. Defensive execution
   All requires and function calls are wrapped in `pcall` to ensure
   robustness during startup and partial failures.

The function itself is exported directly (not wrapped in a table) to allow
simple re-export patterns.
]]--

  -- Normalize `dir` (strip leading/trailing slashes and trailing dots)
  dir = tostring(dir):gsub("^/*", ""):gsub("/*$", ""):gsub("%.+$", "")

  -- Resolve absolute path to the directory under the user's config `lua/`.
  local full_dir = vim.fn.stdpath("config") .. "/lua/" .. dir

  -- Determine the calling module to avoid self-require recursion.
  -- debug.getinfo(2) points to the direct caller of this function.
  local caller_src = debug.getinfo(2, "S")
  local caller_module = nil
  if caller_src and type(caller_src.source) == "string" then
    local src = caller_src.source:gsub("^@", "")
    if src:find("/lua/") then
      local rel = src:match("/lua/(.+)%.lua$")
      if rel then
        caller_module = rel:gsub("/", ".")
      end
    end
  end

  -- Normalize `calls` argument.
  ---@type string[]|nil
  local call_list = nil
  if type(calls) == "string" then
    if calls ~= "" then
      call_list = { calls }
    else
      call_list = {}
    end
  elseif type(calls) == "table" then
    call_list = calls
  end

  -- Find all .lua files within that directory (non-recursive).
  ---@type string[]
  local files = vim.fn.glob(full_dir .. "/*.lua", true, true)

  if #files == 0 then
    notify.warn("[lib.require_dir] No files found in " .. full_dir)
    return
  end

  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r")

    -- Skip "init.lua" to avoid double-loading aggregators.
    if name ~= "init" then
      local module_name = dir .. "." .. name

      -- Skip the calling module itself to prevent recursion.
      if module_name ~= caller_module then
        local ok, mod = pcall(require, module_name)
        if not ok then
          notify.error("[lib.require_dir] Failed to require " .. module_name .. ": " .. tostring(mod))
        else
          -- Function dispatch logic.
          if type(mod) == "table" then
            if call_list == nil then
              -- Default behavior: call setup({})
              if type(mod.setup) == "function" then
                local ok_setup, err = pcall(mod.setup, {})
                if not ok_setup then
                  notify.error("[lib.require_dir] Setup error in " .. module_name .. ": " .. tostring(err))
                end
              end
            else
              -- Explicit function list (possibly empty)
              for _, fn in ipairs(call_list) do
                if type(mod[fn]) == "function" then
                  local ok_call, err = pcall(mod[fn], mod)
                  if not ok_call then
                    notify.error("[lib.require_dir] Error calling " .. fn .. " in " .. module_name .. ": " .. tostring(err))
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

---Lazy-loading wrapper
---@param module_name string
---@return fun(): table
function M.lazy(module_name)
  local cached = nil
  return function()
    if not cached then
      cached = require(module_name)
    end
    return cached
  end
end

---Ensure a lazy.nvim plugin is actually loaded before requiring one of its modules.
---
---Being listed in another plugin's `dependencies` only guarantees installation
---and spec-merging - it does NOT force lazy.nvim to load a dependency that has
---its own lazy triggers (cmd/event/ft/keys). If plugin B's config does
---`require("a_module")` from plugin A, and A is only lazy-loaded via its own
---`cmd`/`event`, that require can run before A ever reached the runtimepath.
---
---This tries, in order: (1) the module is already loaded, (2) ask lazy.nvim to
---load the owning plugin by name, (3) as a last resort, locate the plugin's
---install dir via lazy's own registry and prepend it to `rtp` directly.
---@param plugin_name string lazy.nvim plugin name, e.g. "open.nvim"
---@param module_name string Lua module to require afterwards, e.g. "open_nvim"
---@return boolean ok
---@return any result Module or error message
function M.ensure_plugin(plugin_name, module_name)
  if package.loaded[module_name] then
    return true, package.loaded[module_name]
  end

  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then
    pcall(lazy.load, { plugins = { plugin_name } })
  end

  local ok, mod = M.safe(module_name)
  if ok then
    return true, mod
  end

  if ok_lazy then
    local ok_cfg, plugin = pcall(function()
      return require("lazy.core.config").plugins[plugin_name]
    end)
    if ok_cfg and plugin and plugin.dir then
      vim.opt.rtp:prepend(plugin.dir)
      ok, mod = M.safe(module_name)
      if ok then
        return true, mod
      end
    end
  end

  notify.error(
    ("[ensure_plugin] Could not load '%s' (module '%s'): %s"):format(
      plugin_name,
      module_name,
      tostring(mod)
    )
  )
  return false, mod
end

return M
