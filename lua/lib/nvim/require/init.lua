---@module 'lib.nvim.require'
---Safe and extended require utilities

require("lib.nvim.require.@types")

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

---Load all `*.lua` files directly inside `lua/<dir>` (non-recursive,
---`init.lua` skipped) and dispatch `calls` on each loaded module. The
---calling module itself is skipped (detected via `debug.getinfo`), so a
---module inside `<dir>` that calls this on its own parent directory does
---not re-require itself into infinite recursion. All requires and
---function calls are `pcall`-wrapped; failures are reported via notify
---rather than raised.
---@param dir string Directory relative to lua/
---@param calls? string|string[]|"" Which function(s) to call on each loaded module: nil calls `setup({})` if present (default); a string calls exactly that function; a table calls each in order; `""` calls nothing, modules are only required.
---@return nil
function M.dir(dir, calls)
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
          notify.error(
            "[lib.require_dir] Failed to require " .. module_name .. ": " .. tostring(mod)
          )
        else
          -- Function dispatch logic.
          if type(mod) == "table" then
            if call_list == nil then
              -- Default behavior: call setup({})
              if type(mod.setup) == "function" then
                local ok_setup, err = pcall(mod.setup, {})
                if not ok_setup then
                  notify.error(
                    "[lib.require_dir] Setup error in " .. module_name .. ": " .. tostring(err)
                  )
                end
              end
            else
              -- Explicit function list (possibly empty)
              for _, fn in ipairs(call_list) do
                if type(mod[fn]) == "function" then
                  local ok_call, err = pcall(mod[fn], mod)
                  if not ok_call then
                    notify.error(
                      "[lib.require_dir] Error calling "
                        .. fn
                        .. " in "
                        .. module_name
                        .. ": "
                        .. tostring(err)
                    )
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

--- CDX: reimplements `lib.lua.lazy`'s `LAZY.module(name).get` (cache-on-first-
--- access require) rather than delegating to it; the two now have to be kept
--- behaviorally in sync by hand. Real caller: `LIB.require_lazy` in
--- `lib/strategies/eager.lua`/`lazy.lua`.
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

---@type Lib.Require
return M
