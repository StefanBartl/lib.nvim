-- TESTS/fs_with_lock_spec.lua -- lib.nvim.fs.with_lock: an advisory lock beside a file, busy told from stuck.

return function(H)
  local ok = H.ok
  local with_lock = require("lib.nvim.fs.with_lock")
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

  local function exists(path)
    return uv.fs_lstat(path) ~= nil
  end

  local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
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

  local function seconds_since(t0)
    return (uv.hrtime() - t0) / 1e9
  end

  ---`with_lock` as it behaves on a Windows host or on any other (the module asks for the platform once, when it
  ---loads: a fresh copy is loaded against a stubbed answer, and the real modules are put back).
  ---@param windows boolean
  ---@return function with_lock
  local function with_lock_on(windows)
    local plat, mod = "lib.nvim.cross.platform.is_windows", "lib.nvim.fs.with_lock"
    local saved_plat, saved_mod = package.loaded[plat], package.loaded[mod]
    package.loaded[plat] = function()
      return windows
    end
    package.loaded[mod] = nil
    local loaded, fresh = pcall(require, mod)
    package.loaded[plat], package.loaded[mod] = saved_plat, saved_mod
    if not loaded then
      error(fresh, 0)
    end
    return fresh
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local target = dir .. "/locked.md"
  write(target, "x")
  local lock = dir .. "/.locked.md.lock"

  -- ── the lock exists while the function runs, and what it answers comes back (up to three values) ──
  local a, b, c = with_lock(target, function()
    ok(exists(lock), "the lock file exists while the function runs")
    return "one", "two", { three = true }
  end)
  eq({ a, b, c }, { "one", "two", { three = true } })
  ok(not exists(lock), "and is gone afterwards")
  eq(
    with_lock(target, function()
      return nil, "an answer of its own"
    end),
    nil,
    "(nil, err) of the function is handed on"
  )
  ok(not exists(lock))

  -- ── an error of the function propagates, as it was raised, and the lock is released on the way out ──
  local raised, rerr = pcall(with_lock, target, function()
    error("boom", 0)
  end)
  eq(raised, false)
  eq(rerr, "boom", "no position added")
  ok(not exists(lock), "the lock is released")

  -- ── the lock file holds the pid of its holder, then a token of this acquisition ──
  local tokens = {}
  for i = 1, 2 do
    with_lock(target, function()
      local lines = H.read_lines(lock)
      eq(tonumber(lines[1]), uv.os_getpid(), "the holder")
      eq(#lines, 2, "and a token on the second line")
      tokens[i] = lines[2]
    end)
  end
  ok(tokens[1] ~= tokens[2], "each acquisition has a token of its own")

  -- ── a holder that overran stale_s must not delete the lock of the process that took over ──
  -- (the successor's lock is made exactly as a takeover makes it: the old file deleted, a new one created)
  local create_real = require("lib.nvim.fs.create_exclusive")
  local lock_slashed = (lock:gsub("\\", "/"))
  local function successor_takes_over()
    uv.fs_unlink(lock)
    assert(create_real(lock, "4242\nsuccessor"))
  end
  eq(
    with_lock(target, function()
      successor_takes_over()
      return "finished"
    end),
    "finished",
    "the overrunning holder still gets its answer"
  )
  ok(exists(lock), "the lock of the successor survives the release of the overrunning holder")
  eq(H.read_lines(lock)[1], "4242", "and it is still the successor's")
  os.remove(lock)
  -- ... also when the overrunning holder ends in an error
  local late_ok, late_err = pcall(with_lock, target, function()
    successor_takes_over()
    error("late boom", 0)
  end)
  eq({ late_ok, late_err }, { false, "late boom" }, "the error still propagates")
  ok(exists(lock), "and the successor's lock survives that release too")
  os.remove(lock)
  -- ... a lock that is gone by itself is nothing to release, and no error
  eq(
    with_lock(target, function()
      os.remove(lock)
      return "alone"
    end),
    "alone",
    "a lock that vanished is no error"
  )
  ok(not exists(lock))
  -- ... a lock that cannot be read is deleted as before: a happy path never leaves one behind for stale_s
  local real_open = uv.fs_open
  H.with_patched(uv, "fs_open", function(p, flags, ...)
    if flags == "r" and p == lock_slashed then
      return nil, "EACCES: permission denied"
    end
    return real_open(p, flags, ...)
  end, function()
    eq(
      with_lock(target, function()
        return "unreadable"
      end),
      "unreadable"
    )
  end)
  ok(not exists(lock), "a lock that cannot be read is deleted as before")
  -- ... also when it opens and the read then fails
  H.with_patched(uv, "fs_read", function()
    return nil, "EIO: i/o error"
  end, function()
    eq(
      with_lock(target, function()
        return "read fails"
      end),
      "read fails"
    )
  end)
  ok(not exists(lock), "a lock whose read fails is deleted as before")

  -- ── the lock sits beside the file, hidden, named after it (also for a backslash path on Windows) ──
  if vim.fn.has("win32") == 1 then
    local seen
    with_lock((dir .. "/locked.md"):gsub("/", "\\"), function()
      seen = exists(lock)
    end)
    eq(seen, true, "a backslash path names the same lock")
  end

  -- ── a lock held by someone else: wait, then give up with a message that says busy ──
  write(lock, "1234")
  local t0 = uv.hrtime()
  local none, busy, info = with_lock(target, function()
    return "never"
  end, { wait_ms = 80 })
  eq(none, nil)
  has(busy, "being written by another process")
  eq(info.code, "locked", "a lock someone holds right now is busy")
  eq(info.retryable, true, "and asking again can help")
  eq(info.lock, (lock:gsub("\\", "/")), "the lock file, with forward slashes")
  ok(seconds_since(t0) < 1.5, "the wait is bounded")
  ok(seconds_since(t0) >= 0.07, "and it did wait")
  ok(exists(lock), "a lock that is not ours stays")

  -- ── one older than the stale limit belongs to a process that died: taken over ──
  local old = os.time() - 120
  uv.fs_utime(lock, old, old)
  eq(
    with_lock(target, function()
      return "took over"
    end),
    "took over"
  )
  ok(not exists(lock))

  -- ... the limit is the caller's to set
  write(lock, "1")
  local five = os.time() - 5
  uv.fs_utime(lock, five, five)
  local young = with_lock(target, function()
    return "never"
  end, { wait_ms = 50 })
  eq(young, nil, "5 s old is not stale for the default 10 s")
  eq(
    with_lock(target, function()
      return "took over early"
    end, { stale_s = 2 }),
    "took over early",
    "but it is for stale_s = 2"
  )

  -- ── two waiters judge the SAME stale lock: the slow one must not delete the fresh lock of the first ──
  -- (deterministic: right after the age of the lock was read by `with_lock`, a successor does its whole takeover)
  local guard = lock .. ".takeover"
  write(lock, "1")
  uv.fs_utime(lock, old, old)
  local real_lstat = uv.fs_lstat
  local fired = false
  local slow_ran = false
  local sn, _, sinfo
  H.with_patched(uv, "fs_lstat", function(p, ...)
    local st, e, n = real_lstat(p, ...)
    local caller = debug.getinfo(2, "S").source
    if not fired and p == lock_slashed and st and caller:find("with_lock[/\\]init%.lua") then
      fired = true
      uv.fs_unlink(lock)
      assert(create_real(lock, "P1"))
    end
    return st, e, n
  end, function()
    sn, _, sinfo = with_lock(target, function()
      slow_ran = true
      return "never"
    end, { wait_ms = 150 })
  end)
  eq(fired, true, "the successor's takeover did run between the age check and the delete")
  eq(slow_ran, false, "the slow waiter did not run in the successor's critical section")
  eq(sn, nil)
  eq(sinfo and sinfo.code, "locked", "it is told the lock is held")
  eq(H.read_lines(lock)[1], "P1", "and the successor's lock is still there")
  ok(not exists(guard), "the takeover guard is not left behind")
  os.remove(lock)

  -- ... a guard left by a taker that died is judged by the same age rule
  write(lock, "1")
  uv.fs_utime(lock, old, old)
  write(guard, "999999")
  uv.fs_utime(guard, old, old)
  eq(
    with_lock(target, function()
      return "after the dead taker"
    end, { wait_ms = 1000 }),
    "after the dead taker",
    "a stale guard does not block the takeover"
  )
  ok(not exists(guard), "and it is removed")
  ok(not exists(lock))

  -- ... a young guard is a taker at work right now: the takeover waits for it
  write(lock, "1")
  uv.fs_utime(lock, old, old)
  write(guard, "999999")
  local young_ran = false
  local gn = with_lock(target, function()
    young_ran = true
    return "never"
  end, { wait_ms = 100 })
  eq({ gn, young_ran }, { nil, false }, "a young guard is respected: nobody enters")
  ok(exists(lock) and exists(guard), "and neither file was touched")
  os.remove(lock)
  os.remove(guard)

  -- ── a folder where the lock file should be is stuck at once, without waiting ──
  vim.fn.mkdir(lock, "p")
  t0 = uv.hrtime()
  local nope, msg, linfo = with_lock(target, function()
    return "never"
  end, { wait_ms = 5000 })
  eq(nope, nil)
  eq(linfo.code, "lock_stuck")
  eq(linfo.retryable, false)
  has(msg, "remove it by hand")
  ok(seconds_since(t0) < 1, "no waiting for a lock nobody can release")
  vim.fn.delete(lock, "d")

  -- ── an old lock that cannot be deleted does not spin past the deadline ──
  write(lock, "1")
  uv.fs_utime(lock, old, old)
  local n2, m2, i2
  t0 = uv.hrtime()
  H.with_patched(uv, "fs_unlink", function()
    return nil, "EBUSY"
  end, function()
    n2, m2, i2 = with_lock(target, function()
      return "never"
    end, { wait_ms = 100 })
  end)
  eq(n2, nil)
  has(m2, "remove it by hand")
  eq(i2.code, "lock_stuck", "an old lock that cannot be deleted is stuck, not busy")
  eq(i2.retryable, false)
  ok(seconds_since(t0) < 1.5, "the deadline holds for a lock that cannot be removed")
  os.remove(lock)
  os.remove(guard) -- the stubbed unlink could not remove the takeover guard either

  -- ── EPERM / EACCES / EBUSY: contention on Windows (a delete still pending), waited out ──
  local on_windows, elsewhere = with_lock_on(true), with_lock_on(false)
  for _, word in ipairs({ "EPERM", "EACCES", "EBUSY" }) do
    local tries = 0
    local got = on_windows(target, function()
      return "got it"
    end, {
      create_exclusive = function(path, text)
        tries = tries + 1
        if tries < 3 then
          return false, "open failed: " .. word .. ": operation not permitted"
        end
        return create_real(path, text)
      end,
    })
    eq(got, "got it", word .. " is waited out on Windows")
    eq(tries, 3)

    -- ... anywhere else it is a refusal of the folder, not a writer: io at once, one try
    tries = 0
    t0 = uv.hrtime()
    local en, emsg, einfo = elsewhere(target, function()
      return "never"
    end, {
      wait_ms = 5000,
      create_exclusive = function()
        tries = tries + 1
        return false, "open failed: " .. word .. ": operation not permitted"
      end,
    })
    eq(en, nil, word .. " off Windows")
    eq(einfo and einfo.code, "io", word .. " is a real failure off Windows")
    eq(einfo and einfo.retryable, false)
    has(emsg, "cannot lock")
    has(emsg, word)
    eq(tries, 1, "no second try")
    ok(seconds_since(t0) < 1, "no waiting for a refusal that will not get better")
  end

  -- ── a refusal no writer explains: the name is free and the create is still denied (read-only folder, ACL) ──
  -- not `locked`/retryable (asking again never helps); the wait stays, a pending delete may still be finishing
  local denied = function()
    return false, "open failed: EACCES: permission denied"
  end
  t0 = uv.hrtime()
  local dn, dmsg, dinfo = on_windows(target, function()
    return "never"
  end, { wait_ms = 100, create_exclusive = denied })
  eq(dn, nil)
  eq(dinfo and dinfo.code, "io", "a denied create is an io failure, not a busy lock")
  eq(dinfo and dinfo.retryable, false, "and asking again will not help")
  eq(dinfo and dinfo.lock, lock_slashed)
  has(dmsg, "cannot lock")
  has(dmsg, "EACCES")
  ok(seconds_since(t0) >= 0.09, "it waited out the deadline first")
  ok(seconds_since(t0) < 1.5, "and the wait is bounded")
  -- ... but with something at the lock path (a delete that is still pending shows as a file) it stays contention
  write(lock, "1234")
  local pn, _, pinfo = on_windows(target, function()
    return "never"
  end, { wait_ms = 100, create_exclusive = denied })
  eq(pn, nil)
  eq(pinfo and pinfo.code, "locked", "something at the lock path: still contention")
  eq(pinfo and pinfo.retryable, true)
  os.remove(lock)

  -- ── any other error of the create is a real failure: io, not retryable, no waiting ──
  t0 = uv.hrtime()
  local nn, ioerr, ioinfo = with_lock(target, function()
    return "never"
  end, {
    wait_ms = 5000,
    create_exclusive = function()
      return false, "open failed: ENOSPC: no space left"
    end,
  })
  eq(nn, nil)
  has(ioerr, "cannot lock")
  has(ioerr, "ENOSPC")
  eq(ioinfo.code, "io")
  eq(ioinfo.retryable, false)
  ok(seconds_since(t0) < 1, "no waiting for something that will not get better")

  -- ── a dangling link where the lock file should be is stuck at once; nothing is made at its target ──
  -- (Windows' O_EXCL follows a dangling link and would create the lock at the target, outside the folder)
  local outside = dir .. "/outside"
  vim.fn.mkdir(outside, "p")
  local planted = outside .. "/planted.txt"
  if uv.fs_symlink(planted, lock) then
    local ran = false
    t0 = uv.hrtime()
    local ln, lmsg, lnfo = with_lock(target, function()
      ran = true
      return "never"
    end, { wait_ms = 100 })
    local lst = uv.fs_lstat(lock)
    eq(ln, nil)
    eq(lnfo and lnfo.code, "lock_stuck", "a link is not a lock that can be taken")
    eq(lnfo and lnfo.retryable, false)
    has(lmsg, "remove it by hand")
    eq(ran, false, "the function did not run")
    eq(uv.fs_stat(planted), nil, "nothing is created at the link target")
    eq(lst and lst.type, "link", "and the link is not removed")
    ok(seconds_since(t0) < 1, "no waiting for a lock nobody can release")
    uv.fs_unlink(lock)
  else
    H.skipped("fs_with_lock: dangling link as the lock", "this host cannot create symbolic links")
  end

  -- ... and so is a link to a file that EXISTS (a link, not the folder of the case above, and not dangling: Windows
  -- follows a dangling one, so only this one shows that the type decides, not the folder)
  local linked_file = dir .. "/lock-target.txt"
  write(linked_file, "keep")
  if uv.fs_symlink(linked_file, lock) then
    local ran_link = false
    t0 = uv.hrtime()
    local fn_, fmsg, finfo = with_lock(target, function()
      ran_link = true
      return "never"
    end, { wait_ms = 1500 })
    local link_st = uv.fs_lstat(lock)
    eq(fn_, nil)
    eq(finfo and finfo.code, "lock_stuck", "a link to a file is no lock that can be taken either")
    eq(finfo and finfo.retryable, false)
    has(fmsg, "remove it by hand")
    eq(ran_link, false, "the function did not run")
    ok(seconds_since(t0) < 1, "it is told at once, not after the wait")
    eq(link_st and link_st.type, "link", "and the link is not removed")
    eq(H.read_lines(linked_file), { "keep" }, "nor the file it points to changed")
    uv.fs_unlink(lock)
  else
    H.skipped("fs_with_lock: link to a file as the lock", "this host cannot create symbolic links")
  end

  -- ── a path that names no file is an io failure: no lock, no folder, no hidden leftovers ──
  local before = listing(dir)
  local cwd = vim.fn.chdir(dir) -- "" has no folder of its own: the lock would be made in the current one
  local named, after = {}, nil
  -- the current folder is put back whatever happens (later specs and the two-process case build paths from it)
  local named_ok, named_err = pcall(function()
    for i, bad in ipairs({ dir .. "/sub/", dir .. "\\sub\\", "" }) do
      local fn_ran = false
      local r, m, binfo = with_lock(bad, function()
        fn_ran = true
        return "never"
      end, { wait_ms = 100 })
      named[i] = { bad = bad, res = r, msg = m, info = binfo, ran = fn_ran }
    end
    after = listing(dir)
  end)
  vim.fn.chdir(cwd)
  ok(named_ok, named_err)
  for _, r in ipairs(named) do
    local what = ("%q"):format(r.bad)
    eq(r.res, nil, what)
    has(r.msg, "names no file", what)
    eq(r.info and r.info.code, "io", what)
    eq(r.info and r.info.retryable, false, what)
    eq(r.info and r.info.lock, "", what .. ": there is no lock file")
    eq(r.ran, false, what .. ": the function did not run")
  end
  eq(after, before, "no folder 'sub' and no hidden lock tree were made")

  -- ── a bare file name locks in the current folder ──
  -- (the current folder is put back whatever happens: the two-process case below builds its runtime path from it)
  local bare_dir = dir .. "/cwd"
  vim.fn.mkdir(bare_dir, "p")
  local bare_lock = bare_dir .. "/.bare.md.lock"
  local before_bare = vim.fn.chdir(bare_dir)
  local bare_ok, bare_res = pcall(with_lock, "bare.md", function()
    ok(exists(bare_lock), "the lock file is made in the current folder")
    return "x"
  end, { wait_ms = 100 })
  vim.fn.chdir(before_bare)
  ok(bare_ok, bare_res)
  eq(bare_res, "x", "a bare file name works")
  ok(not exists(bare_lock), "and the lock is released")

  -- ── a lock in a folder that does not exist yet: the parent is made (the lock file is a create like any) ──
  local fresh = dir .. "/new-folder/doc.md"
  eq(
    with_lock(fresh, function()
      return "ok"
    end),
    "ok"
  )
  ok(not exists(dir .. "/new-folder/.doc.md.lock"))
  local made = uv.fs_lstat(dir .. "/new-folder")
  eq(made and made.type, "directory", "and the folder it made stays (documented)")

  -- ── the lock is per path, not per caller: not re-entrant (documented) ──
  local inner_ran = false
  local nested, nmsg, ninfo = with_lock(target, function()
    return with_lock(target, function()
      inner_ran = true
      return "never"
    end, { wait_ms = 100 })
  end)
  eq(nested, nil, "a nested lock on the same path does not get in")
  eq(inner_ran, false)
  has(nmsg, "being written by another process")
  eq(ninfo and ninfo.code, "locked", "it answers locked although the holder is the caller itself")
  ok(not exists(lock), "and the outer lock is released as usual")

  -- ── the lock is keyed by the spelling of the path: a hard link takes another lock (documented) ──
  local alias = dir .. "/alias.md"
  if uv.fs_link(target, alias) then
    local alias_in = with_lock(target, function()
      return with_lock(alias, function()
        return "inner"
      end, { wait_ms = 100 })
    end)
    eq(alias_in, "inner", "another spelling of the same file is another lock")
    ok(not exists(lock) and not exists(dir .. "/.alias.md.lock"), "and both are released")
    uv.fs_unlink(alias)
  else
    H.skipped("fs_with_lock: hard link spelling", "this host cannot create hard links")
  end

  -- ── a contended call cannot run in a fast-event context (it raises E5560), an uncontended one can ──
  local fast = {}
  local function answer(word)
    return function()
      return word
    end
  end
  local timer = assert(uv.new_timer())
  timer:start(0, 0, function()
    fast.in_fast_event = vim.in_fast_event()
    fast.free = { pcall(with_lock, target, answer("free")) }
    write(lock, "1234")
    fast.busy = { pcall(with_lock, target, answer("never"), { wait_ms = 50 }) }
    os.remove(lock)
    fast.done = true
  end)
  ok(
    vim.wait(5000, function()
      return fast.done
    end, 10),
    "the timer callback ran"
  )
  timer:stop()
  timer:close()
  os.remove(lock)
  eq(fast.in_fast_event, true, "the callback is a fast-event context")
  eq(fast.free, { true, "free" }, "an uncontended call works there")
  eq(fast.busy and fast.busy[1], false, "a contended call raises instead of answering locked")
  has(fast.busy and fast.busy[2], "fast event", "E5560: vim.wait is not allowed there")

  -- ── two real processes: the second waits for the first, or is told it is busy ──
  local script = dir .. "/holder.lua"
  write(
    script,
    ([[
vim.opt.rtp:append(%q)
local with_lock = require("lib.nvim.fs.with_lock")
local uv = vim.uv or vim.loop
with_lock(%q, function()
  uv.sleep(900)
end)
]]):format(vim.fn.getcwd(), target)
  )
  local child = vim.system(
    { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", script },
    { text = true }
  )
  ok(
    vim.wait(8000, function()
      return exists(lock)
    end, 20),
    "the other process took the lock"
  )
  local n3, m3, i3 = with_lock(target, function()
    return "never"
  end, { wait_ms = 100 })
  eq(n3, nil, "while the other holds it")
  eq(i3.code, "locked")
  has(m3, "being written by another process")
  local second = with_lock(target, function()
    return "second"
  end, { wait_ms = 8000 })
  eq(second, "second", "and after it let go, this one gets it")
  local done = child:wait(8000)
  eq(done.code, 0, "the other process ended well: " .. tostring(done.stderr))
  ok(not exists(lock), "nothing is left behind")

  vim.fn.delete(dir, "rf")
end
