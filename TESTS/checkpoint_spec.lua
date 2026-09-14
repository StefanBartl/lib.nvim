-- TESTS/checkpoint_spec.lua — lib.nvim.checkpoint

---@diagnostic disable: need-check-nil

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

  -- --------------------------------------------------- discard: idempotent

  local existing_c = dir .. "/c.txt"
  write_file(existing_c, "hello c")
  local cp3 = checkpoint.create({ existing_c }, { dir = checkpoint_root })
  ok(cp3 ~= nil, "create: a third checkpoint is created fine")
  ---@cast cp3 -nil

  eq(checkpoint.discard(cp3), true, "discard: first call succeeds")
  eq(uv.fs_stat(cp3.dir), nil, "discard: the backup directory is gone")
  eq(
    checkpoint.discard(cp3),
    true,
    "discard: a second call on an already-discarded checkpoint is a no-op success, not a failure"
  )

  -- ------------------------------------------------- create: cleans up on failure
  --
  -- If a later path in the list fails to back up, create() must not leave
  -- the partially-built checkpoint (already-copied backups, the directory
  -- itself) behind on disk -- the caller only gets `nil, err`, with no
  -- handle to clean it up otherwise.

  do
    local function list_entries(d)
      local entries = {}
      local handle = uv.fs_scandir(d)
      if handle then
        while true do
          local name = uv.fs_scandir_next(handle)
          if not name then
            break
          end
          entries[#entries + 1] = name
        end
      end
      return entries
    end

    local before = list_entries(checkpoint_root)

    local existing_d = dir .. "/d.txt"
    write_file(existing_d, "hello d")
    -- A directory passes fs_stat() (so create() treats it as "existing" and
    -- attempts to back it up) but fs_copyfile() on a directory fails --
    -- deterministic, portable way to force a mid-loop failure.
    local dir_as_path = dir .. "/d_is_a_dir"
    vim.fn.mkdir(dir_as_path, "p")

    local failed_cp, failed_err = checkpoint.create(
      { existing_d, dir_as_path },
      { dir = checkpoint_root }
    )
    eq(failed_cp, nil, "create: reports nil on a mid-loop backup failure")
    ok(failed_err ~= nil, "create: ...with an error message")

    local after = list_entries(checkpoint_root)
    eq(
      #after,
      #before,
      "create: no orphaned checkpoint directory survives a failed create() (entry count under checkpoint_root is unchanged)"
    )
  end

  -- ------------------------------------------------- create: input validation

  do
    ---@diagnostic disable-next-line: param-type-mismatch
    local pcall_ok, cp_result, err_result = pcall(checkpoint.create, nil)
    ok(pcall_ok, "create: a non-table paths argument does not raise")
    eq(cp_result, nil, "create: a non-table paths argument returns nil (not a checkpoint)")
    ok(err_result ~= nil, "create: ...with an error message")
  end

  ok(true, "checkpoint spec completed")
end
