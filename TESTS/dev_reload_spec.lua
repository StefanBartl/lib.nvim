-- TESTS/dev_reload_spec.lua — lib.nvim.dev.reload

return function(H)
  local eq, ok = H.eq, H.ok

  local reload = require("lib.nvim.dev.reload")

  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/lua", "p")

  ---@param name string dotted module path under root/lua
  ---@param body string
  local function write_module(name, body)
    local path = root .. "/lua/" .. name:gsub("%.", "/") .. ".lua"
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local fd = assert(io.open(path, "w"))
    fd:write(body)
    fd:close()
  end

  vim.opt.rtp:append(root)

  write_module("dev_reload_fixture", "return { value = 1 }")
  local first = require("dev_reload_fixture")
  eq(first.value, 1, "first require reads the on-disk value")

  -- Same module, changed on disk, cache not yet touched: a plain require()
  -- must still answer from the cache (this is the behavior reload() exists
  -- to bypass, not a claim about M.module() itself).
  write_module("dev_reload_fixture", "return { value = 2 }")
  local cached = require("dev_reload_fixture")
  eq(cached.value, 1, "package.loaded still holds the stale table")

  local reloaded_ok = reload.module("dev_reload_fixture")
  ok(reloaded_ok, "module() reports success for a module that loads cleanly")
  local fresh = require("dev_reload_fixture")
  eq(fresh.value, 2, "module() actually cleared the cache -- fresh value wins")

  -- A module that later breaks: module() reports failure instead of raising,
  -- and does not leave the OLD, working cache entry in place pretending to
  -- still be current -- the cache is cleared up front, before the reload is
  -- even attempted, not only on success.
  write_module("dev_reload_broken", "return { value = 'good' }")
  local good = require("dev_reload_broken")
  eq(good.value, "good", "the working version loads normally first")

  write_module("dev_reload_broken", "error('boom')")
  local broken_ok = reload.module("dev_reload_broken")
  ok(not broken_ok, "module() reports failure for a module whose chunk now errors")
  -- Not just "not the old table": Lua's own require() leaves a truthy,
  -- non-nil, non-table remnant in package.loaded[name] after an erroring
  -- loader (reproduced independently of this module -- see reload.lua's own
  -- comment on M.module), which a later plain require(name) would treat as
  -- "already loaded" and hand back as-is. module() must clear that away too.
  eq(
    package.loaded["dev_reload_broken"],
    nil,
    "no truthy remnant is left for a later require() to pick up"
  )
end
