-- docs/TESTS/cwd_spec.lua — lib.nvim.fs.chdir, lib.nvim.fs.dir_guard, and the
-- skip_dirs / max_depth bounds added to lib.nvim.fs.find_root.

local chdir = require("lib.nvim.fs.chdir")
local dir_guard = require("lib.nvim.fs.dir_guard")
local find_root = require("lib.nvim.fs.find_root")
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

return function(H)
  local original_cwd = vim.fn.getcwd()

  -- ── fs.chdir ───────────────────────────────────────────────────────────────
  do
    local root = make_tree({ "a/b/" })

    local ok, err = chdir(root .. "/a/b")
    H.ok(ok, "chdir into an existing directory: " .. tostring(err))
    H.eq(normkey(vim.fn.getcwd()), root .. "/a/b", "cwd after global chdir")

    -- A trailing slash must not survive into the cwd: `getcwd()` never has one,
    -- and callers compare the two directly.
    H.ok(chdir(root .. "/a/"), "chdir with a trailing slash")
    H.eq(normkey(vim.fn.getcwd()), root .. "/a", "trailing slash stripped")

    -- Rejected before the command runs, never thrown.
    local bad_ok, bad_err = chdir(root .. "/does/not/exist")
    H.eq(bad_ok, false, "chdir into a missing directory fails")
    H.ok(bad_err and bad_err:match("not a directory"), "missing directory is reported")

    local file_ok = chdir(root)
    H.ok(file_ok, "chdir back to the tree root")

    local scope_ok, scope_err = chdir(root, { scope = "nope" })
    H.eq(scope_ok, false, "unknown scope is rejected")
    H.ok(scope_err and scope_err:match("unknown scope"), "unknown scope is reported")

    -- Window-local scope leaves the global cwd untouched.
    local global_before = vim.fn.getcwd(-1, -1)
    H.ok(chdir(root .. "/a", { scope = "win" }), "window-local chdir")
    H.eq(normkey(vim.fn.getcwd(0, 0)), root .. "/a", "window cwd changed")
    H.eq(vim.fn.getcwd(-1, -1), global_before, "global cwd untouched by :lcd")
    vim.cmd("noautocmd cd " .. vim.fn.fnameescape(original_cwd))
  end

  -- ── fs.dir_guard ───────────────────────────────────────────────────────────
  do
    local root = make_tree({ "held/", "elsewhere/" })

    local held, err = dir_guard.hold(root .. "/held")
    H.ok(held, "guard established: " .. tostring(err))
    H.eq(held.path(), root .. "/held", "guard reports the held path")

    -- A foreign change is undone.
    vim.cmd("cd " .. vim.fn.fnameescape(root .. "/elsewhere"))
    H.eq(normkey(vim.fn.getcwd()), root .. "/held", "foreign chdir was reverted")

    -- bypass() lets the caller move, then restores.
    local bypass_saw
    held.bypass(function()
      vim.cmd("cd " .. vim.fn.fnameescape(root .. "/elsewhere"))
      bypass_saw = normkey(vim.fn.getcwd())
    end)
    H.eq(bypass_saw, root .. "/elsewhere", "bypass allows the change")
    H.eq(normkey(vim.fn.getcwd()), root .. "/held", "bypass restores the pin")

    -- update() moves the pin and keeps guarding.
    H.ok(held.update(root .. "/elsewhere"), "update moves the pin")
    H.eq(held.path(), root .. "/elsewhere", "pin moved")
    vim.cmd("cd " .. vim.fn.fnameescape(root .. "/held"))
    H.eq(normkey(vim.fn.getcwd()), root .. "/elsewhere", "new pin is enforced")

    held.release()
    H.eq(held.is_held(), false, "released guard reports it")
    vim.cmd("cd " .. vim.fn.fnameescape(root .. "/held"))
    H.eq(normkey(vim.fn.getcwd()), root .. "/held", "released guard stops enforcing")

    -- on_violation returning false accepts the change and drops the guard.
    local seen_new, seen_held
    local soft = dir_guard.hold(root .. "/held", {
      on_violation = function(new_cwd, held_dir)
        seen_new, seen_held = new_cwd, held_dir
        return false
      end,
    })
    H.ok(soft, "second guard established")
    vim.cmd("cd " .. vim.fn.fnameescape(root .. "/elsewhere"))
    H.eq(normkey(vim.fn.getcwd()), root .. "/elsewhere", "accepted change stands")
    H.eq(seen_new, root .. "/elsewhere", "on_violation got the new cwd")
    H.eq(seen_held, root .. "/held", "on_violation got the held dir")
    H.eq(soft.is_held(), false, "guard released itself")

    H.eq(dir_guard.hold(root .. "/nope"), nil, "hold on a missing directory fails")

    vim.cmd("noautocmd cd " .. vim.fn.fnameescape(original_cwd))
  end

  -- ── find_root: skip_dirs ───────────────────────────────────────────────────
  do
    local root = make_tree({
      ".git/",
      "package.json",
      "node_modules/pkg/package.json",
      "node_modules/pkg/lib/x.js",
      "node_modules/a/node_modules/b/package.json",
      "node_modules/a/node_modules/b/lib/y.js",
    })

    local plain = find_root({ markers = { ".git", "package.json" } })
    H.eq(
      normkey(plain.find(root .. "/node_modules/pkg/lib/x.js")),
      root .. "/node_modules/pkg",
      "without skip_dirs the vendored package wins"
    )

    local skipping = find_root({
      markers = { ".git", "package.json" },
      skip_dirs = { "node_modules" },
    })
    H.eq(
      normkey(skipping.find(root .. "/node_modules/pkg/lib/x.js")),
      root,
      "skip_dirs resolves past the vendor directory"
    )
    H.eq(
      normkey(skipping.find(root .. "/node_modules/a/node_modules/b/lib/y.js")),
      root,
      "nested vendor trees resolve to the outer project"
    )
    H.eq(
      normkey(skipping.find(root .. "/node_modules")),
      root,
      "the skipped directory itself resolves to its parent's root"
    )
    -- Second lookup comes from the cache — same answer, keyed by the queried dir.
    H.eq(
      normkey(skipping.find(root .. "/node_modules/pkg/lib/x.js")),
      root,
      "cached skip_dirs lookup agrees"
    )

    local chained = find_root({
      markers = { ".git", "package.json" },
      skip_dirs = { "node_modules" },
      cache_chain = true,
    })
    H.eq(
      normkey(chained.find(root .. "/node_modules/pkg/lib/x.js")),
      root,
      "skip_dirs also applies on the chain-caching path"
    )
    H.eq(
      normkey(chained.find(root .. "/node_modules/pkg/lib/x.js")),
      root,
      "chain-cached skip_dirs lookup agrees"
    )
  end

  -- ── find_root: max_depth ───────────────────────────────────────────────────
  do
    local root = make_tree({ ".git/", "a/b/c/x.lua" })

    local unbounded = find_root({ markers = { ".git" } })
    H.eq(normkey(unbounded.find(root .. "/a/b/c/x.lua")), root, "unbounded walk finds the root")

    -- The marker sits 3 levels above the queried directory.
    local too_shallow = find_root({ markers = { ".git" }, max_depth = 2 })
    H.eq(too_shallow.find(root .. "/a/b/c/x.lua"), nil, "max_depth stops short of the root")

    local deep_enough = find_root({ markers = { ".git" }, max_depth = 3 })
    H.eq(normkey(deep_enough.find(root .. "/a/b/c/x.lua")), root, "max_depth reaches the root")

    local here_only = find_root({ markers = { ".git" }, max_depth = 0 })
    H.eq(here_only.find(root .. "/a/b/c/x.lua"), nil, "max_depth 0 searches only the queried dir")
    H.eq(normkey(here_only.find(root .. "/x.lua")), root, "max_depth 0 still matches in place")

    local chained = find_root({ markers = { ".git" }, max_depth = 2, cache_chain = true })
    H.eq(chained.find(root .. "/a/b/c/x.lua"), nil, "max_depth also bounds the chain walk")
  end

  vim.cmd("noautocmd cd " .. vim.fn.fnameescape(original_cwd))
end
