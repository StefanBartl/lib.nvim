-- TESTS/polymorphic_rootresolver_spec.lua — lib.nvim.fs.polymorphic_rootresolver.
--
-- The argument normalization is what this module is for: every LSP root_dir
-- resolver has to turn a buffer number or a filename into a directory, cope
-- with an unnamed buffer, and honour the optional callback the vim.lsp
-- contract allows. Reimplementing that is how three copies of it appear in one
-- config, which is what the `resolve` hook exists to prevent.

local resolver = require("lib.nvim.fs.polymorphic_rootresolver")
local normkey = require("lib.nvim.fs.normkey")

---Build a throwaway directory tree; returns its (normalized) root.
---@param spec string[] Relative paths; a trailing "/" means directory, else file.
---@return string
local function make_tree(spec)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  for _, rel in ipairs(spec) do
    local full = root .. "/" .. rel
    if rel:sub(-1) == "/" then
      vim.fn.mkdir(full, "p")
    else
      vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
      local f = io.open(full, "w")
      if f then
        f:write("x")
        f:close()
      end
    end
  end
  return normkey(root)
end

---@param H table
return function(H)
  -- ── marker search ─────────────────────────────────────────────────────
  do
    local root = make_tree({ ".git/", "src/main.lua" })
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })

    H.eq(normkey(resolve(root .. "/src/main.lua")), root, "finds the marker upward from a filename")
  end

  do
    local root = make_tree({ "src/main.lua" })
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })

    H.eq(
      normkey(resolve(root .. "/src/main.lua")),
      normkey(root .. "/src"),
      "falls back to the file's own directory when no marker is found"
    )
  end

  -- ── argument shapes ───────────────────────────────────────────────────
  do
    local root = make_tree({ ".git/", "src/main.lua" })
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, root .. "/src/main.lua")
    H.eq(normkey(resolve(bufnr)), root, "accepts a buffer number")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  do
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })
    local empty = vim.api.nvim_create_buf(false, true)
    H.ok(resolve(empty) ~= nil, "an unnamed buffer still yields a directory")
    vim.api.nvim_buf_delete(empty, { force = true })
  end

  -- ── callback contract ─────────────────────────────────────────────────
  do
    local root = make_tree({ ".git/", "a.lua" })
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })

    local seen
    local returned = resolve(root .. "/a.lua", function(r)
      seen = r
    end)
    H.eq(normkey(seen), root, "the callback receives the root")
    H.eq(normkey(returned), root, "and it is returned synchronously as well")
  end

  do
    local root = make_tree({ ".git/", "a.lua" })
    local resolve = resolver({ markers = { ".git" }, include_stdpath_config = false })

    -- A throwing callback must not take the resolution with it: root_dir is on
    -- the attach path, and a broken consumer should cost its own callback, not
    -- the server's chance of starting.
    local returned = resolve(root .. "/a.lua", function()
      error("consumer exploded")
    end)
    H.eq(normkey(returned), root, "a throwing callback does not break the resolver")
  end

  -- ── resolve hook ──────────────────────────────────────────────────────
  do
    local root = make_tree({ ".git/", "src/main.lua" })
    local seen_dir
    local resolve = resolver({
      include_stdpath_config = false,
      resolve = function(dir)
        seen_dir = dir
        return "/custom/root"
      end,
    })

    H.eq(resolve(root .. "/src/main.lua"), "/custom/root", "the hook replaces the marker search")
    H.eq(normkey(seen_dir), normkey(root .. "/src"), "the hook receives the normalized directory")
  end

  do
    local root = make_tree({ "src/main.lua" })
    local resolve = resolver({
      include_stdpath_config = false,
      resolve = function()
        return nil
      end,
    })

    H.eq(
      normkey(resolve(root .. "/src/main.lua")),
      normkey(root .. "/src"),
      "nil from the hook falls back to the starting directory"
    )
  end

  do
    local root = make_tree({ "src/main.lua" })
    local resolve = resolver({
      include_stdpath_config = false,
      resolve = function()
        error("hook exploded")
      end,
    })

    H.eq(
      normkey(resolve(root .. "/src/main.lua")),
      normkey(root .. "/src"),
      "a throwing hook degrades to the starting directory instead of propagating"
    )
  end

  do
    local root = make_tree({ ".git/", "a.lua" })
    local called = false
    local resolve = resolver({
      markers = { ".git" },
      include_stdpath_config = false,
      resolve = function()
        called = true
        return nil
      end,
    })
    resolve(root .. "/a.lua")
    H.ok(called, "the hook takes precedence over markers when both are given")
  end

  -- ── include_stdpath_config = true (the default) ────────────────────────
  --
  -- Every case above sets this `false`. It defaults to `true`, and the change
  -- that introduced `stdpath_config_root` here touched exactly one line --
  -- `root = stdpath_config_root(root) or root` -- which none of the cases
  -- above exercises. Assertions here are on the RAW return value, not
  -- `normkey(...)`-wrapped, since the point of two of these is the exact
  -- spelling that comes back, which `normkey` would launder away.

  -- Shared with stdpath_config_root_spec.lua and dev_reload_spec.lua -- see
  -- TESTS/harness.lua for why this used to be three separate copies.
  local with_stdpath_config = H.with_stdpath_config

  do
    -- No marker anywhere, so the plain marker search would answer the file's
    -- own directory -- `stdpath_config_root` has to be what pulls the root up
    -- to the stubbed config dir instead.
    local config = make_tree({ "lua/plugins/" })
    local file = config .. "/lua/plugins/init.lua"
    vim.fn.writefile({}, file)

    -- The assertion runs inside an outer pcall so `vim.fn.delete` below still
    -- runs on a failure, not only on success -- `with_stdpath_config` itself
    -- re-raises past its own restore, which would otherwise skip this cleanup
    -- entirely and leak the temp directory.
    local test_ok, test_err = pcall(function()
      with_stdpath_config(config, function()
        local resolve = resolver({ markers = { ".git" } })
        H.eq(resolve(file), config, "a file under the (stubbed) config dir roots there")
      end)
    end)
    vim.fn.delete(config, "rf")
    assert(test_ok, test_err)
  end

  do
    -- The `or root` fallback: a file OUTSIDE the config dir must still
    -- resolve to whatever the marker search (or file-own-directory fallback)
    -- already found, not fall through to the config dir.
    local root = make_tree({ ".git/", "src/main.lua" })
    local config = make_tree({})

    local test_ok, test_err = pcall(function()
      with_stdpath_config(config, function()
        local resolve = resolver({ markers = { ".git" } })
        H.eq(
          normkey(resolve(root .. "/src/main.lua")),
          root,
          "a file outside the config dir keeps its own root"
        )
      end)
    end)
    vim.fn.delete(root, "rf")
    vim.fn.delete(config, "rf")
    assert(test_ok, test_err)
  end

  -- The symlinked-dotfiles case reaching this call site specifically -- see
  -- TESTS/stdpath_config_root_spec.lua for the full case on the module
  -- itself; this pins that `polymorphic_rootresolver` actually calls through
  -- to it, with the raw return value, rather than e.g. comparing against the
  -- root the marker search already found before `stdpath_config_root` runs.
  do
    local base = normkey(vim.fn.tempname())
    vim.fn.mkdir(base .. "/dotfiles/nvim/lua", "p")
    local link = base .. "/config_link"
    local sym_ok, sym_err = (vim.uv or vim.loop).fs_symlink(
      base .. "/dotfiles/nvim",
      link,
      { dir = true, junction = false }
    )

    -- One cleanup point below, run exactly once regardless of which branch
    -- below takes, and regardless of whether the assertion inside it raises
    -- -- `test_ok`/`test_err` default to a no-op "pass" for the skip branch,
    -- which does not itself assert anything.
    local test_ok, test_err = true, nil

    if sym_ok ~= true then
      local message = "polymorphic_rootresolver_spec: SKIPPED — needs a real directory symlink, "
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
      local file = base .. "/dotfiles/nvim/lua/init.lua"
      vim.fn.writefile({}, file)

      test_ok, test_err = pcall(function()
        with_stdpath_config(link, function()
          local resolve = resolver({ markers = { ".git" } })
          H.eq(
            resolve(file),
            normkey(link),
            "a symlinked config dir still roots there through this call site"
          )
        end)
      end)
    end

    pcall(vim.fn.delete, base, "rf")
    assert(test_ok, test_err)
  end
end
