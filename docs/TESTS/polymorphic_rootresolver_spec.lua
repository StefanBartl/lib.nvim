-- docs/TESTS/polymorphic_rootresolver_spec.lua — lib.nvim.fs.polymorphic_rootresolver.
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
end
