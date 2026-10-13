-- TESTS/fs_create_exclusive_spec.lua -- lib.nvim.fs.create_exclusive: create a file or learn it was already there.

return function(H)
  local ok = H.ok
  local create = require("lib.nvim.fs.create_exclusive")
  local uv = vim.uv or vim.loop

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local function read(path)
    local f = io.open(path, "rb")
    if not f then
      return nil
    end
    local text = f:read("*a")
    f:close()
    return text
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  -- ── surface ──
  eq(type(create), "table", "a callable table")
  eq(create.EXISTS, "exists")
  ok(create.is_exists("exists"), "the word")
  ok(not create.is_exists("open failed: EACCES"), "another error")
  ok(not create.is_exists(nil), "nil")

  -- ── creates the parents and writes the bytes as given ──
  local path = dir .. "/a/b/new.md"
  local made, err = create(path, "one\r\ntwo\0three")
  eq({ made, err }, { true, nil })
  eq(read(path), "one\r\ntwo\0three", "no newline added, NUL and CRLF kept")

  -- ── the second one learns it was too late, and the file is not touched ──
  local again, aerr = create(path, "other")
  eq(again, false)
  ok(create.is_exists(aerr), "exists: " .. tostring(aerr))
  eq(read(path), "one\r\ntwo\0three", "the first writer's bytes stay")

  -- ── an empty content is a real, empty file ──
  local empty = dir .. "/empty.md"
  ok(create(empty, ""), "empty content")
  eq(read(empty), "")
  ok(not select(1, create(empty, "x")), "and it counts as present")

  -- ── a folder on the path counts as present; a file where a parent should be is a real error ──
  local as_dir = dir .. "/folder"
  vim.fn.mkdir(as_dir, "p")
  local blocked, berr = create(as_dir, "x")
  eq(blocked, false)
  ok(create.is_exists(berr), "a folder with that name: exists")
  local under_file, uerr = create(path .. "/child.md", "x")
  eq(under_file, false)
  ok(
    not create.is_exists(uerr),
    "a file where a folder should be is no 'exists': " .. tostring(uerr)
  )

  -- ── any other failure to open is a real error, not 'exists' ──
  local real_open = uv.fs_open
  uv.fs_open = function()
    return nil, "EACCES: permission denied"
  end
  local denied, derr = create(dir .. "/denied.md", "x")
  uv.fs_open = real_open
  eq(denied, false)
  ok(not create.is_exists(derr), "a denied open is no 'exists'")
  ok(tostring(derr):find("open failed", 1, true) and tostring(derr):find("EACCES", 1, true), derr)

  -- ── a write that fails leaves no file that the next caller would read as 'exists' ──
  local real_write = uv.fs_write
  uv.fs_write = function()
    return nil, "ENOSPC: no space left on device"
  end
  local full = dir .. "/full.md"
  local fok, ferr = create(full, "x")
  uv.fs_write = real_write
  eq(fok, false)
  ok(tostring(ferr):find("write failed", 1, true), "the error names the step: " .. tostring(ferr))
  eq(uv.fs_stat(full), nil, "the half-made file is removed again")
  ok(create(full, "x"), "and the name is free")

  -- ... a short write counts as failed too
  uv.fs_write = function()
    return 1
  end
  local short = dir .. "/short.md"
  local sok = create(short, "abc")
  uv.fs_write = real_write
  eq(sok, false, "a short write")
  eq(uv.fs_stat(short), nil, "is removed")

  -- ── exactly one of many creators wins ──
  local race = dir .. "/race.md"
  local wins = 0
  for i = 1, 20 do
    if create(race, tostring(i)) then
      wins = wins + 1
    end
  end
  eq(wins, 1, "one winner")
  eq(read(race), "1", "the first one")

  vim.fn.delete(dir, "rf")
end
