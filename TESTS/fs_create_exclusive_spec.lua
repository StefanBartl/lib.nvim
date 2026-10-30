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

  local function has(text, part, msg)
    ok(type(text) == "string" and text:find(part, 1, true), msg or ("expected " .. part))
  end

  ---Sorted `name:type` entries of a folder, to see that nothing was added to it.
  local function listing(folder)
    local list, handle = {}, uv.fs_scandir(folder)
    while handle do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      list[#list + 1] = name .. ":" .. kind
    end
    table.sort(list)
    return list
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

  -- ── a parent that exists is not walked again: the folders are only made when the open says they are missing ──
  local walks = { mkdir = 0, stat = 0 }
  H.with_patched(uv, "fs_mkdir", function()
    walks.mkdir = walks.mkdir + 1
    return nil, "EACCES: the spec forbids folders here"
  end, function()
    H.with_patched(uv, "fs_stat", function()
      walks.stat = walks.stat + 1
      return nil, "ENOENT: the spec forbids stat here"
    end, function()
      made, err = create(dir .. "/a/b/second.md", "2")
    end)
  end)
  eq({ made, err }, { true, nil }, "the parent exists: created")
  eq(walks, { mkdir = 0, stat = 0 }, "without walking the folder chain")
  eq(read(dir .. "/a/b/second.md"), "2")
  -- ... a missing parent is still made, and the create then goes through
  made, err = create(dir .. "/c/d/e/deep.md", "3")
  eq({ made, err }, { true, nil }, "a missing parent chain")
  eq(read(dir .. "/c/d/e/deep.md"), "3")
  -- ... and a parent that cannot be made is the error of mkdirp, not 'exists'
  local mk_ok, mk_err
  H.with_patched(uv, "fs_mkdir", function()
    return nil, "EACCES: permission denied"
  end, function()
    mk_ok, mk_err = create(dir .. "/nope/x.md", "x")
  end)
  eq(mk_ok, false, "a parent that cannot be made")
  ok(not create.is_exists(mk_err), "is no 'exists': " .. tostring(mk_err))
  has(mk_err, "mkdirp: cannot create")

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

  -- ── a link at the name counts as present, a dangling one too: nothing is made at its target ──
  -- (Windows' O_EXCL follows a dangling link and creates the file, or a folder, at the target)
  local outside = dir .. "/outside"
  vim.fn.mkdir(outside, "p")
  local planted = outside .. "/planted.txt"
  local claimed = dir .. "/claimed.md"
  if uv.fs_symlink(planted, claimed) then
    local lok, lerr = create(claimed, "payload")
    eq(lok, false, "a dangling file link")
    ok(create.is_exists(lerr), "is present: " .. tostring(lerr))
    eq(uv.fs_stat(planted), nil, "nothing is created at the link target")
    local lst = uv.fs_lstat(claimed)
    eq(lst and lst.type, "link", "and the link is not removed")
    uv.fs_unlink(claimed)
  else
    H.skipped("fs_create_exclusive: dangling file link", "this host cannot create symbolic links")
  end
  local nodir = outside .. "/nodir"
  local dir_link = dir .. "/dirlink.md"
  if uv.fs_symlink(nodir, dir_link, { dir = true }) then
    local dok, derr2 = create(dir_link, "payload")
    eq(dok, false, "a dangling folder link")
    ok(create.is_exists(derr2), "is present: " .. tostring(derr2))
    eq(uv.fs_stat(nodir), nil, "no folder is created at the link target")
    local dst = uv.fs_lstat(dir_link)
    eq(dst and dst.type, "link", "and the user's link is not deleted")
    uv.fs_unlink(dir_link)
  else
    H.skipped("fs_create_exclusive: dangling folder link", "this host cannot create symbolic links")
  end

  -- ── the name is taken while the missing parent is made: looked up again before the second open ──
  -- (deterministic: right after mkdirp makes the parent, a rival plants a dangling link at the name, or a plain
  -- file where links cannot be made. Windows' O_EXCL would follow the link and write at its target; the second
  -- lstat is the only lock there, so the create must answer 'exists' without opening the name again.)
  local raced_parent = dir .. "/race_parent"
  local raced_name = raced_parent .. "/x.md"
  local raced_target = outside .. "/target.md"
  local real_mkdir, real_fs_open2 = uv.fs_mkdir, uv.fs_open
  local planted_as, opens_after = nil, 0
  local pok, perr
  H.with_patched(uv, "fs_mkdir", function(p, ...)
    local r1, r2 = real_mkdir(p, ...)
    if r1 and not planted_as and p:gsub("\\", "/"):match("/race_parent$") then
      if uv.fs_symlink(raced_target, raced_name) then
        planted_as = "link"
      else
        local fd = assert(real_fs_open2(raced_name, "w", 420))
        uv.fs_write(fd, "RIVAL", 0)
        uv.fs_close(fd)
        planted_as = "file"
      end
    end
    return r1, r2
  end, function()
    H.with_patched(uv, "fs_open", function(p, ...)
      if planted_as and p == raced_name then
        opens_after = opens_after + 1
      end
      return real_fs_open2(p, ...)
    end, function()
      pok, perr = create(raced_name, "payload")
    end)
  end)
  ok(planted_as ~= nil, "the rival came in while the parent was made")
  eq(pok, false, "the name taken meanwhile (" .. tostring(planted_as) .. ")")
  ok(create.is_exists(perr), "is present: " .. tostring(perr))
  eq(opens_after, 0, "the name is not opened again once it is taken")
  eq(uv.fs_stat(raced_target), nil, "nothing is written at the link target")
  local rst = uv.fs_lstat(raced_name)
  eq(rst and rst.type, planted_as, "the rival's entry is left as it was")
  if planted_as == "file" then
    eq(read(raced_name), "RIVAL", "the rival's bytes stay")
  end
  uv.fs_unlink(raced_name)
  eq(listing(outside), {}, "nothing was written outside")

  -- ── a path that ends in a slash names a folder: an error, never 'exists', and no folder is made ──
  local slash_ok, slash_err = create(dir .. "/t/T-1/", "x")
  eq(slash_ok, false)
  ok(
    not create.is_exists(slash_err),
    "no 'exists' for a name that did not exist: " .. tostring(slash_err)
  )
  has(slash_err, "open failed")
  eq(uv.fs_stat(dir .. "/t/T-1"), nil, "the folder with the file's name is not made")
  eq(uv.fs_stat(dir .. "/t"), nil, "nor its parent")
  local bslash_ok, bslash_err = create(dir .. "/t/T-2\\", "x")
  eq(bslash_ok, false, "a trailing backslash is a separator too")
  ok(not create.is_exists(bslash_err), tostring(bslash_err))
  eq(uv.fs_stat(dir .. "/t"), nil, "and makes nothing")

  -- ── a bad argument is answered, never raised: no file is claimed and no descriptor leaks ──
  local bad = dir .. "/n.md"
  local cases = {
    { "nil path", nil, "x" },
    { "nil content", bad, nil },
    { "number content", bad, 42 },
    { "table content", bad, {} },
    { "number path", 12, "x" },
    -- libuv cuts the path at the NUL: without the check this would create `bad` itself
    { "NUL in path", bad .. "\0.tail", "x" },
  }
  local opens, closes = 0, 0
  local real_fs_open, real_fs_close = uv.fs_open, uv.fs_close
  local results = {}
  -- (the stubs are put back whatever happens inside: a leaked `uv.fs_open` would fail every later spec of the run)
  H.with_patched(uv, "fs_open", function(...)
    opens = opens + 1
    return real_fs_open(...)
  end, function()
    H.with_patched(uv, "fs_close", function(...)
      closes = closes + 1
      return real_fs_close(...)
    end, function()
      for i, case in ipairs(cases) do
        local called, bok, berr2 = pcall(create, case[2], case[3])
        results[i] = { called = called, ok = bok, err = berr2, stat = uv.fs_stat(bad) }
      end
    end)
  end)
  for i, case in ipairs(cases) do
    local r = results[i]
    eq(r.called, true, case[1] .. ": never raises (" .. tostring(r.ok) .. ")")
    eq(r.ok, false, case[1])
    has(r.err, "invalid arguments", case[1])
    eq(r.stat, nil, case[1] .. ": no file is left as a claim")
  end
  eq(opens, closes, "every opened descriptor is closed")
  ok(create(bad, "x"), "and the name is still free")

  -- ── any other failure to open is a real error, not 'exists' ──
  local denied, derr
  H.with_patched(uv, "fs_open", function()
    return nil, "EACCES: permission denied"
  end, function()
    denied, derr = create(dir .. "/denied.md", "x")
  end)
  eq(denied, false)
  ok(not create.is_exists(derr), "a denied open is no 'exists'")
  ok(tostring(derr):find("open failed", 1, true) and tostring(derr):find("EACCES", 1, true), derr)

  -- ── a write that fails leaves no file that the next caller would read as 'exists' ──
  local full = dir .. "/full.md"
  local fok, ferr
  H.with_patched(uv, "fs_write", function()
    return nil, "ENOSPC: no space left on device"
  end, function()
    fok, ferr = create(full, "x")
  end)
  eq(fok, false)
  ok(tostring(ferr):find("write failed", 1, true), "the error names the step: " .. tostring(ferr))
  eq(uv.fs_stat(full), nil, "the half-made file is removed again")
  ok(create(full, "x"), "and the name is free")

  -- ... a short write counts as failed too
  local short = dir .. "/short.md"
  local sok
  H.with_patched(uv, "fs_write", function()
    return 1
  end, function()
    sok = create(short, "abc")
  end)
  eq(sok, false, "a short write")
  eq(uv.fs_stat(short), nil, "is removed")

  -- ── a second creator, and every later one, learns it was too late (one after the other: no race yet) ──
  local race = dir .. "/race.md"
  local wins = 0
  for i = 1, 20 do
    if create(race, tostring(i)) then
      wins = wins + 1
    end
  end
  eq(wins, 1, "one winner")
  eq(read(race), "1", "the first one")

  -- ── a rival that creates the file between any look at the name and the create: only the exclusive open survives ──
  -- (deterministic: the first open of the name is preceded by the rival's whole create; a check-then-create, or a
  -- plain "w" open, would answer success and overwrite the rival's bytes)
  local raced = dir .. "/raced.md"
  local real_open = uv.fs_open
  local rival_came = false
  local rmade, rerr
  H.with_patched(uv, "fs_open", function(p, flags, mode, ...)
    if p == raced and not rival_came then
      rival_came = true
      local fd = assert(real_open(p, "w", 420))
      uv.fs_write(fd, "RIVAL", 0)
      uv.fs_close(fd)
    end
    return real_open(p, flags, mode, ...)
  end, function()
    rmade, rerr = create(raced, "mine")
  end)
  eq(rival_came, true, "the rival got in before the create")
  eq(rmade, false, "the one that came second was refused")
  ok(create.is_exists(rerr), "and told it was too late: " .. tostring(rerr))
  eq(read(raced), "RIVAL", "the rival's bytes are intact")

  vim.fn.delete(dir, "rf")
end
