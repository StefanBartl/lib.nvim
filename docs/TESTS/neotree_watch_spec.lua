-- docs/TESTS/neotree_watch_spec.lua — lib.nvim.neotree.watch
--
-- Neo-tree itself isn't a test dependency: `install()` only needs
-- `neo-tree.sources.filesystem.lib.fs_watch` to be *requirable*, so a
-- minimal fake is registered in `package.loaded` under that name, giving
-- full control over what `watch_folder`/`stop_watching` do without a real
-- neo-tree.nvim installation.

return function(H)
  local eq, ok = H.eq, H.ok

  local uv = vim.uv or vim.loop
  local FS_WATCH_MODNAME = "neo-tree.sources.filesystem.lib.fs_watch"

  local watch = require("lib.nvim.neotree.watch")

  -- Fake fs_watch: `watch_folder` returns a fresh Watcher-shaped table per
  -- call (mirrors what the registry actually touches: `active`, `handle`);
  -- `stop_watching` just records that it ran, so the wrap around it can be
  -- verified to still call through.
  local stop_watching_calls = 0
  local fake_fs_watch = {
    watch_folder = function(_path, _callback)
      return { active = true, handle = uv.new_fs_event() }
    end,
    stop_watching = function()
      stop_watching_calls = stop_watching_calls + 1
    end,
  }
  package.loaded[FS_WATCH_MODNAME] = fake_fs_watch

  eq(watch.installed(), false, "watch: not installed before install() is called")
  eq(watch.install(), true, "watch: install() succeeds when fs_watch is requirable")
  eq(watch.installed(), true, "watch: installed() reflects the patch")
  eq(watch.install(), true, "watch: install() is idempotent (second call still true)")

  -- watch_folder is now the WRAPPED function (install() mutates the fake
  -- table's field in place) -- calling it is standing in for neo-tree
  -- expanding a directory in the tree.
  local dir1 = "C:/tmp/lib-nvim-spec/dir1"
  local dir2 = "C:/tmp/lib-nvim-spec/dir2"
  fake_fs_watch.watch_folder(dir1, function() end)
  fake_fs_watch.watch_folder(dir2, function() end)

  eq(watch.count(), 2, "watch: watch_folder wrap records every watcher created")

  local snapshot = watch.list()
  eq(#snapshot, 2, "watch.list(): one entry per tracked watcher")
  local by_path = {}
  for _, entry in ipairs(snapshot) do
    by_path[entry.path] = entry
  end
  ok(
    by_path["c:/tmp/lib-nvim-spec/dir1"] ~= nil,
    "watch.list(): path normalized (lowercase drive, forward slashes)"
  )
  eq(
    by_path["c:/tmp/lib-nvim-spec/dir1"].active,
    true,
    "watch.list(): freshly tracked watcher is active"
  )

  -- ---------------------------------------------------------- release()
  --
  -- The actual bug this test guards against: an earlier version of
  -- `release()` deleted the registry entry after releasing it. Since
  -- neo-tree can restart the SAME Watcher object on the same path later
  -- (`updated_watched()`) without ever calling `watch_folder` again, that
  -- meant a path could only ever be released ONCE -- a second mutation on
  -- the same directory would find nothing to release and hit the exact
  -- EPERM lock this module exists to prevent.

  local released_1 = watch.release(dir1)
  eq(released_1, 1, "release(): closes the tracked watcher on an exact path match")
  eq(
    watch.count(),
    2,
    "release(): the watcher STAYS in the registry (not forgotten) so it can be released again"
  )

  local released_again = watch.release(dir1)
  eq(
    released_again,
    1,
    "release(): releasing the SAME path a second time still finds and releases it"
  )

  -- Releasing a PARENT path releases every tracked subpath.
  local base = "C:/tmp/lib-nvim-spec"
  local released_parent = watch.release(base)
  eq(released_parent, 2, "release(): releasing a parent path releases every tracked subpath")

  -- A path with nothing tracked under it releases zero, not an error.
  eq(watch.release("C:/somewhere/else"), 0, "release(): an untracked path releases nothing")

  -- Array form releases the union of multiple paths.
  fake_fs_watch.watch_folder(dir1, function() end)
  fake_fs_watch.watch_folder(dir2, function() end)
  eq(watch.release({ dir1, dir2 }), 2, "release(): an array of paths releases the union of matches")

  -- ------------------------------------------------------------ with_release
  --
  -- Releases before fn AND after fn -- the second release catches a watcher
  -- neo-tree may have re-established mid-operation (a refresh/rescan).

  fake_fs_watch.watch_folder(dir1, function() end) -- re-track, simulating a live watcher again
  local active_during = nil
  local ran = watch.with_release(dir1, function()
    for _, entry in ipairs(watch.list()) do
      if entry.path == "c:/tmp/lib-nvim-spec/dir1" then
        active_during = entry.active
      end
    end
    -- Simulate neo-tree re-establishing a watcher on the same path mid-fn
    -- (e.g. a rescan triggered by the mutation itself).
    fake_fs_watch.watch_folder(dir1, function() end)
    return "result"
  end)
  eq(
    active_during,
    false,
    "with_release(): the watcher is already released (inactive) by the time fn runs"
  )
  eq(ran, "result", "with_release(): returns fn's own return value")
  for _, entry in ipairs(watch.list()) do
    if entry.path == "c:/tmp/lib-nvim-spec/dir1" then
      eq(
        entry.active,
        false,
        "with_release(): the watcher re-established during fn is released again afterward"
      )
    end
  end

  local raised_ok, raised_err = pcall(watch.with_release, dir1, function()
    error("boom")
  end)
  eq(raised_ok, false, "with_release(): re-raises an error from fn")
  ok(
    tostring(raised_err):find("boom", 1, true) ~= nil,
    "with_release(): the original error message survives"
  )

  -- ------------------------------------------------------ stop_watching wrap

  local before_stop = watch.count()
  ok(before_stop > 0, "watch: at least one watcher tracked before the stop_watching nuke")
  package.loaded[FS_WATCH_MODNAME].stop_watching()
  eq(
    stop_watching_calls,
    1,
    "install(): the wrapped stop_watching still calls through to the original"
  )
  eq(
    watch.count(),
    0,
    "install(): stop_watching's wrap DOES forget every entry -- neo-tree is discarding them for good"
  )

  -- ---------------------------------------------------------------- clear()

  fake_fs_watch.watch_folder(dir1, function() end)
  ok(watch.count() > 0, "watch: at least one watcher tracked before clear()")
  watch.clear()
  eq(watch.count(), 0, "clear(): forgets every tracked watcher (test-only helper, no handle close)")
end
