-- TESTS/checkpoint_spec.lua — lib.nvim.checkpoint

return function(H)
  local eq, ok = H.eq, H.ok

  local checkpoint = require("lib.nvim.checkpoint")
  local uv = vim.uv or vim.loop

  local function write_file(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  local function read_file(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local content = f:read("*a")
    f:close()
    return content
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local checkpoint_root = dir .. "/backups"

  local existing_a = dir .. "/a.txt"
  local existing_b = dir .. "/b.txt"
  local not_yet = dir .. "/new.txt"

  write_file(existing_a, "hello a")
  write_file(existing_b, "hello b")

  -- ------------------------------------------------------------------ create

  local cp, err = checkpoint.create({ existing_a, existing_b, not_yet }, { dir = checkpoint_root })
  eq(err, nil, "create: no error for a valid path list")
  ok(cp ~= nil, "create: returns a checkpoint")
  ---@cast cp -nil
  eq(#cp.entries, 3, "create: one entry per tracked path")
  eq(cp.entries[1].existed, true, "create: an existing file is marked existed=true")
  eq(cp.entries[1].size, 7, "create: existing entry records the real file size")
  ok(cp.entries[1].backup ~= nil, "create: an existing file gets a backup path")
  eq(cp.entries[3].existed, false, "create: a not-yet-existing path is marked existed=false")
  eq(cp.entries[3].backup, nil, "create: a not-yet-existing path has no backup")

  ok(uv.fs_stat(cp.entries[1].backup) ~= nil, "create: the backup file actually exists on disk")
  eq(
    read_file(cp.entries[1].backup),
    "hello a",
    "create: the backup's content matches the original, byte-exact"
  )

  -- --------------------------------------------------------------- restore

  -- Mutate as if the guarded operation ran: rewrite an existing file,
  -- create the file that didn't exist before.
  write_file(existing_a, "MUTATED")
  write_file(not_yet, "should be removed by restore")

  local restored_ok, restore_errors = checkpoint.restore(cp)
  eq(restored_ok, true, "restore: reports success")
  eq(#restore_errors, 0, "restore: no errors")
  eq(read_file(existing_a), "hello a", "restore: existing file's content is restored byte-exact")
  eq(read_file(existing_b), "hello b", "restore: an untouched file is still correct")
  eq(uv.fs_stat(not_yet), nil, "restore: a file that didn't exist before is removed again")

  -- Restoring again (idempotent: not_yet already gone) must not error.
  local restored_again_ok, restore_again_errors = checkpoint.restore(cp)
  eq(restored_again_ok, true, "restore: is safe to call again (idempotent)")
  eq(#restore_again_errors, 0, "restore: still no errors on the second call")

  -- ------------------------------------------------------------------ discard

  local backup_dir = cp.dir
  ok(uv.fs_stat(backup_dir) ~= nil, "discard: the backup directory exists before discard")

  local discard_ok = checkpoint.discard(cp)
  eq(discard_ok, true, "discard: reports success")
  eq(uv.fs_stat(backup_dir), nil, "discard: the backup directory is gone afterwards")

  -- ------------------------------------------------------------- distinct ids

  local cp2 = checkpoint.create({ existing_b }, { dir = checkpoint_root })
  ok(cp2 ~= nil, "create: a second checkpoint is created fine")
  ---@cast cp2 -nil
  ok(cp2.id ~= cp.id, "create: successive checkpoints get distinct ids")
  checkpoint.discard(cp2)

  ok(true, "checkpoint spec completed")
end
