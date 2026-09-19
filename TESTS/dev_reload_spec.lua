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
  --
  -- Shared with stdpath_config_root_spec.lua and polymorphic_rootresolver_spec.lua
  -- (with_stdpath_config) and general-purpose (with_patched) -- see
  -- TESTS/harness.lua.
  local with_stdpath_config = H.with_stdpath_config
  local with_patched = H.with_patched

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

    -- Everything that can raise runs inside this one pcall, so the augroup,
    -- rtp entry, and temp directory below are all cleaned up whether the
    -- assertion passes or not -- `reload.watch()` registers a REAL
    -- `BufWritePost` autocmd, and one that outlives a failed case here would
    -- keep firing (double-`require()`ing whatever this process saves next)
    -- for the rest of the shared `TESTS/run.lua` process.
    local test_ok, test_err = pcall(function()
      with_stdpath_config(base .. "/cfg", function()
        local reloaded = {}
        local orig_module = reload.module

        -- `with_patched` restores `reload.module` even if the assertion
        -- below raises -- a bare "patch, call, restore" would leave the spy
        -- closure (and its now-dead `reloaded` upvalue) installed as the
        -- module's real `reload()` for every later spec in the process.
        with_patched(reload, "module", function(name)
          reloaded[#reloaded + 1] = name
          return orig_module(name)
        end, function()
          reload.watch({ group = "dev_reload_spec_plain" })
          local bufnr = open_and_write(base .. "/cfg/lua/dev_reload_watch_fixture.lua")
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end)

        eq(
          reloaded[1],
          "dev_reload_watch_fixture",
          "watch() reloads a file saved directly under stdpath('config')/lua"
        )
      end)
    end)

    pcall(vim.api.nvim_del_augroup_by_name, "dev_reload_spec_plain")
    vim.opt.rtp:remove(base .. "/cfg")
    vim.fn.delete(base, "rf")
    assert(test_ok, test_err)
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

    -- One cleanup point below, run exactly once regardless of which branch
    -- runs and whether the assertion inside it raises. Defaults to a no-op
    -- "pass" for the skip branch, which does not itself assert anything.
    local test_ok, test_err = true, nil

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
        test_ok, test_err =
          false, "outside Windows a symlink must be creatable under CI, so: " .. message
      end
    else
      vim.opt.rtp:append(base .. "/dotfiles/nvim")

      test_ok, test_err = pcall(function()
        with_stdpath_config(link, function()
          local reloaded = {}
          local orig_module = reload.module

          with_patched(reload, "module", function(name)
            reloaded[#reloaded + 1] = name
            return orig_module(name)
          end, function()
            reload.watch({ group = "dev_reload_spec_symlink" })
            -- The canonical spelling: what a Unix buffer name carries for a
            -- file opened through the symlink. Windows does not canonicalize
            -- (measured elsewhere in this fleet), so this pins the contract
            -- identically wherever a symlink can be made at all, matching
            -- rootresolvers_spec.lua's own reasoning in lsp.nvim.
            local canonical = base .. "/dotfiles/nvim/lua/dev_reload_watch_symlinked.lua"
            local bufnr = open_and_write(canonical)
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end)

          eq(
            reloaded[1],
            "dev_reload_watch_symlinked",
            "watch() reloads a file whose spelling differs from stdpath('config')'s own"
          )
        end)
      end)

      pcall(vim.api.nvim_del_augroup_by_name, "dev_reload_spec_symlink")
      vim.opt.rtp:remove(base .. "/dotfiles/nvim")
    end

    pcall(vim.fn.delete, base, "rf")
    assert(test_ok, test_err)
  end
end
