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

  local function seconds_since(t0)
    return (uv.hrtime() - t0) / 1e9
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

  -- ── the lock file holds the pid of its holder ──
  with_lock(target, function()
    eq(tonumber(H.read_lines(lock)[1]), uv.os_getpid(), "the holder")
  end)

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
  local real_unlink = uv.fs_unlink
  uv.fs_unlink = function()
    return nil, "EBUSY"
  end
  t0 = uv.hrtime()
  local n2, m2, i2 = with_lock(target, function()
    return "never"
  end, { wait_ms = 100 })
  uv.fs_unlink = real_unlink
  eq(n2, nil)
  has(m2, "remove it by hand")
  eq(i2.code, "lock_stuck", "an old lock that cannot be deleted is stuck, not busy")
  eq(i2.retryable, false)
  ok(seconds_since(t0) < 1.5, "the deadline holds for a lock that cannot be removed")
  os.remove(lock)

  -- ── EPERM / EACCES / EBUSY from a just-removed lock is contention, waited out ──
  for _, word in ipairs({ "EPERM", "EACCES", "EBUSY" }) do
    local tries = 0
    local got = with_lock(target, function()
      return "got it"
    end, {
      create_exclusive = function(path, text)
        tries = tries + 1
        if tries < 3 then
          return false, "open failed: " .. word .. ": operation not permitted"
        end
        return require("lib.nvim.fs.create_exclusive")(path, text)
      end,
    })
    eq(got, "got it", word .. " is waited out")
    eq(tries, 3)
  end

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

  -- ── a lock in a folder that does not exist yet: the parent is made (the lock file is a create like any) ──
  local fresh = dir .. "/new-folder/doc.md"
  eq(
    with_lock(fresh, function()
      return "ok"
    end),
    "ok"
  )
  ok(not exists(dir .. "/new-folder/.doc.md.lock"))

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
