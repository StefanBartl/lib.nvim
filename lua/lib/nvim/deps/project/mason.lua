---@module 'lib.nvim.deps.project.mason'
--- The one place `lib.nvim.deps.project` talks to mason.nvim, and only
--- through `mason-registry` (a soft dependency: every function answers
--- "unknown" / false when Mason is not loadable).
---
--- Why the registry and not the `:Mason` UI or `:MasonInstall`: the registry
--- API is what the UI itself sits on. `Package:install(opts, callback)`
--- queues the job on Mason's own installer (a coroutine runner behind a
--- shared semaphore, so Mason decides how many run at once) and returns an
--- `InstallHandle`; nothing opens a window, nothing steals focus, and the
--- result arrives in the callback. The feasibility check this was built on
--- is written up in the module README.
---
--- Like the rest of `deps.project` this never installs on its own: the
--- caller (`project.install`) has asked the user first.

local M = {}

---@internal
---@return table|nil registry
local function registry()
  local ok, reg = pcall(require, "mason-registry")
  if ok and type(reg) == "table" then
    return reg
  end
  return nil
end

---@internal
---`get_package` raises for a name the registry does not know (and for every
---name while the registry has never been fetched), so it is always guarded.
---@param reg table
---@param name string
---@return table|nil package
local function package_of(reg, name)
  local ok, pkg = pcall(reg.get_package, name)
  if ok and type(pkg) == "table" then
    return pkg
  end
  return nil
end

---Is Mason loadable at all.
---@return boolean
function M.available()
  return registry() ~= nil
end

---Where does the Mason package `name` stand.
---
---  * `"present"`     installed
---  * `"missing"`     known to the registry, not installed
---  * `"unavailable"` Mason is loadable but does not list it (a typo in the
---                    caller's table, or a registry that was never fetched --
---                    the two look the same from here; see `refresh`)
---  * `"unknown"`     Mason is not loadable
---@param name string
---@return "present"|"missing"|"unavailable"|"unknown" state
function M.status(name)
  local reg = registry()
  if not reg then
    return "unknown"
  end
  local pkg = package_of(reg, name)
  if not pkg then
    return "unavailable"
  end
  local ok, installed = pcall(pkg.is_installed, pkg)
  if ok and installed then
    return "present"
  end
  return "missing"
end

---Fetch the registry if Mason has never done so (fresh machine) or its
---cache is stale (Mason's `registry.refresh` decides by age). `on_done(ok)`
---is called once; with `false`, right away, when Mason is not loadable or
---has no `refresh`.
---@param on_done fun(ok: boolean)
---@return nil
function M.refresh(on_done)
  local reg = registry()
  if not reg or type(reg.refresh) ~= "function" then
    on_done(false)
    return
  end
  local ok = pcall(reg.refresh, function(success)
    vim.schedule(function()
      on_done(success ~= false)
    end)
  end)
  if not ok then
    on_done(false)
  end
end

---Install the Mason packages `names`, headless, each reporting once.
---`on_each(name, ok, err)` fires per package (scheduled onto the main loop);
---`on_done(results)` once after the last, with `results[name] = true|false`.
---A package that is already installed, already installing, or unknown to the
---registry is reported as `false` with a reason and not started.
---@param names string[]
---@param on_each? fun(name: string, ok: boolean, err: string|nil)
---@param on_done? fun(results: table<string, boolean>)
---@return nil
function M.install(names, on_each, on_done)
  local results, pending = {}, #names
  local function settle(name, ok, err)
    results[name] = ok
    if on_each then
      pcall(on_each, name, ok, err)
    end
    pending = pending - 1
    if pending == 0 and on_done then
      pcall(on_done, results)
    end
  end

  if pending == 0 then
    if on_done then
      on_done(results)
    end
    return
  end

  M.refresh(function()
    local reg = registry()
    for _, name in ipairs(names) do
      local pkg = reg and package_of(reg, name) or nil
      if not pkg then
        settle(name, false, "not in the Mason registry")
      else
        local busy_ok, busy = pcall(pkg.is_installing, pkg)
        local done_ok, done = pcall(pkg.is_installed, pkg)
        if busy_ok and busy then
          settle(name, false, "already installing")
        elseif done_ok and done then
          settle(name, false, "already installed")
        else
          local started, err = pcall(pkg.install, pkg, {}, function(success, result)
            vim.schedule(function()
              settle(name, success == true, success and nil or tostring(result))
            end)
          end)
          if not started then
            settle(name, false, tostring(err))
          end
        end
      end
    end
  end)
end

return M
