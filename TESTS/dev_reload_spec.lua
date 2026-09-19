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

  -- ── M.watch() ──────────────────────────────────────────────────────────
  --
  -- Previously untested: the module had coverage for `M.module()` only.
  -- `M.watch()` used to bake `stdpath("config")/lua` in as a single spelling
  -- at registration time, which is exactly the two-spelling comparison
  -- `lib.nvim.fs.stdpath_config_root` exists to fix -- these cases pin that
  -- the fix actually reaches this caller, the third place the pattern lived.

  ---@param link string
  ---@param fn fun(): nil
  local function with_stdpath_config(link, fn)
    local orig = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == "config" then
        return link
      end
      return orig(what)
    end
    local run_ok, err = pcall(fn)
    vim.fn.stdpath = orig
    assert(run_ok, err)
  end

  ---@param bufname string
  ---@return integer bufnr
  local function open_and_write(bufname)
    vim.fn.mkdir(vim.fs.dirname(bufname), "p")
    local bufnr = vim.fn.bufadd(bufname)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "return { value = 'watched' }" })
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write!")
    end)
    return bufnr
  end

  do
    local base = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(base .. "/cfg/lua", "p")
    vim.opt.rtp:append(base .. "/cfg")

    with_stdpath_config(base .. "/cfg", function()
      local reloaded = {}
      local orig_module = reload.module
      reload.module = function(name)
        reloaded[#reloaded + 1] = name
        return orig_module(name)
      end

      reload.watch({ group = "dev_reload_spec_plain" })
      local bufnr = open_and_write(base .. "/cfg/lua/dev_reload_watch_fixture.lua")

      reload.module = orig_module
      vim.api.nvim_buf_delete(bufnr, { force = true })

      eq(
        reloaded[1],
        "dev_reload_watch_fixture",
        "watch() reloads a file saved directly under stdpath('config')/lua"
      )
    end)

    vim.fn.delete(base, "rf")
  end

  -- The symlinked-dotfiles regression: `stdpath("config")` answering a
  -- symlink, and the buffer carrying the OTHER spelling of the same
  -- directory -- reproduced with a real directory symlink, not a stub of
  -- `stdpath_config_root` itself, so this exercises the real dependency.
  do
    local base = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(base .. "/dotfiles/nvim/lua", "p")
    base = require("lib.nvim.fs.normkey")(base)

    local link = base .. "/config_link"
    local sym_ok, sym_err = (vim.uv or vim.loop).fs_symlink(
      base .. "/dotfiles/nvim",
      link,
      { dir = true, junction = false }
    )

    if sym_ok ~= true then
      -- Loud, not silent -- see TESTS/stdpath_config_root_spec.lua for why a
      -- quietly-skipped case is worse than no case at all, and why Windows is
      -- the only platform this is allowed to happen on.
      local message = "dev_reload_spec: SKIPPED — needs a real directory symlink, "
        .. "which this machine refused: "
        .. tostring(sym_err)
      io.stderr:write("\n" .. message .. "\n")
      io.stdout:write(message .. "\n")
      local ci = vim.env.CI
      if ci ~= nil and ci ~= "" and ci ~= "false" and vim.fn.has("win32") ~= 1 then
        error("outside Windows a symlink must be creatable under CI, so: " .. message, 0)
      end
    else
      vim.opt.rtp:append(base .. "/dotfiles/nvim")

      with_stdpath_config(link, function()
        local reloaded = {}
        local orig_module = reload.module
        reload.module = function(name)
          reloaded[#reloaded + 1] = name
          return orig_module(name)
        end

        reload.watch({ group = "dev_reload_spec_symlink" })
        -- The canonical spelling: what a Unix buffer name carries for a file
        -- opened through the symlink. Windows does not canonicalize (measured
        -- elsewhere in this fleet), so this pins the contract identically
        -- wherever a symlink can be made at all, matching
        -- rootresolvers_spec.lua's own reasoning in lsp.nvim.
        local canonical = base .. "/dotfiles/nvim/lua/dev_reload_watch_symlinked.lua"
        local bufnr = open_and_write(canonical)

        reload.module = orig_module
        vim.api.nvim_buf_delete(bufnr, { force = true })

        eq(
          reloaded[1],
          "dev_reload_watch_symlinked",
          "watch() reloads a file whose spelling differs from stdpath('config')'s own"
        )
      end)
    end

    pcall(vim.fn.delete, base, "rf")
  end
end
