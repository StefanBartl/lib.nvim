---@module 'lib.nvim.fs.with_lock'
--- Run a function while holding an advisory lock on a path.
---
--- The lock is a hidden `.<name>.lock` file next to `path`, created exclusively (`lib.nvim.fs.create_exclusive`).
--- Every process that read-modify-writes the same file goes through it, so two of them (an agent's command line and
--- an editor plugin) never start from the same text and drop each other's change. It serialises the COOPERATING
--- writers only; an editor with the file open is not one of them.
---
--- The lock file holds the pid of its holder on its first line and a token of this acquisition on the second. A holder
--- that died leaves its file behind: a lock older than `opts.stale_s` (10 s; a locked write takes milliseconds) is
--- taken over, one waiter at a time (a `.<name>.lock.takeover` file beside it, made exclusively and removed within
--- microseconds, tells the others to wait; it is itself judged stale after `stale_s`). The release deletes the lock
--- only while it still holds the token of THIS call: a holder that overran `stale_s` and was taken over from must not
--- delete the lock of its successor. That is a best-effort compare-then-delete, not an atomic one, so keep `fn` well
--- below `stale_s`. Waiting is bounded (`opts.wait_ms`, 2 s), then `nil, err, info`.
---
--- Limits of the lock:
--- - It is keyed by the SPELLING of the path (its folder and file name): a hard link or a symlink to the same file
---   takes a different lock, so cooperating writers must agree on one path for a file.
--- - It is not re-entrant: it is per path, not per caller. A `with_lock` on the same path from inside `fn` (a save
---   hook that writes again) waits `wait_ms` and answers `locked`, although the lock file holds your own pid.
--- - The folder of the lock is created when it is missing (`create_exclusive` makes the parent) and it stays: a
---   mistyped folder name leaves a new empty folder behind.
--- - While a lock is contended the call blocks the editor loop (`vim.wait` in steps of 10 ms). For that reason a
---   contended call cannot run in a fast-event context (a uv timer or another libuv callback): it raises E5560
---   instead of answering `locked`. An uncontended call works there; `vim.schedule` the call when the context is
---   unknown.
---
--- `info.code` says why: `locked` (someone holds it right now, another process or your own call further up the
--- stack; asking again can help, `retryable`), `lock_stuck` (a lock that nobody will release: older than the takeover
--- age and not deletable, or a folder or link where the lock file should be, a dangling one included; remove it by
--- hand) or `io` (the lock file could not be made, among them a refusal that no writer explains (a read-only folder, a
--- denied ACL), or `path` names no file: it is empty or ends in a slash, and `info.lock` is `""`). What `fn` answers
--- (up to three values) is handed back; an error of `fn` is raised again after the lock is released. The codes are
--- those of `lib.nvim.contract.errors`.
---
--- Moved here from `tasks_nvim.fsio.with_lock` (tasks.nvim@921a0c4). Not to be confused with
--- `lib.nvim.cross.fs.lock`, which diagnoses who holds a file open on Windows.
---
---```lua
--- local with_lock = require("lib.nvim.fs.with_lock")
--- local res, err, info = with_lock(path, function()
---   -- read, change, write
---   return "done"
--- end, { wait_ms = 500 })
--- if res == nil and info and info.retryable then
---   -- ask again later
--- end
---```

require("lib.nvim.fs.with_lock.@types")

local create_exclusive = require("lib.nvim.fs.create_exclusive")
local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")
local is_windows = require("lib.nvim.cross.platform.is_windows")

local uv = vim.uv or vim.loop

---Whether the error of a create is contention and not a real failure. On Windows a lock that was unlinked a moment
---ago answers EPERM / EACCES / EBUSY to a create until the delete completes. Elsewhere those words are a real
---refusal (a folder that denies the create), never a writer: they fail at once.
---@param err any
---@return boolean exists
---@return boolean transient
local function contention(err)
  local exists = create_exclusive.is_exists(err)
  local transient = exists
    or (
      is_windows()
      and type(err) == "string"
      and (
          err:find("EPERM", 1, true)
          or err:find("EACCES", 1, true)
          or err:find("EBUSY", 1, true)
        )
        ~= nil
    )
  return exists, transient
end

---Delete a lock that was judged stale. Several waiters can judge the SAME stale file: a bare delete by name lets a
---slow one delete the fresh lock another has made in the meantime, and both run. So one waiter at a time takes over
---(a `.takeover` file beside the lock, made exclusively), and the age is read again inside it: a lock that is no
---longer stale is somebody's and stays. The guard is made with the real `create_exclusive`, not the `opts` seam,
---which simulates failures of the lock file itself.
---@param lock string
---@param stale_s number
local function take_over(lock, stale_s)
  local guard = lock .. ".takeover"
  if create_exclusive(guard, tostring(uv.os_getpid())) then
    local now = uv.fs_lstat(lock)
    if now and now.type == "file" and os.time() - now.mtime.sec > stale_s then
      pcall(uv.fs_unlink, lock)
    end
    pcall(uv.fs_unlink, guard)
    return
  end
  -- somebody else is taking over (wait), or a taker died inside the microseconds it holds the guard: same age rule
  local held = uv.fs_lstat(guard)
  if held and os.time() - held.mtime.sec > stale_s then
    pcall(uv.fs_unlink, guard)
  end
end

---Release the lock of this acquisition. A holder that overran `stale_s` was taken over from, and the file now at the
---lock path is its successor's: it is deleted only while it still holds OUR token. A lock that cannot be read is
---deleted as before, so a happy path never leaves one behind for `stale_s`.
---@param lock string
---@param token string
local function release(lock, token)
  local fd, open_err = uv.fs_open(lock, "r", 438) -- 0666, less the umask
  if not fd then
    if not tostring(open_err):match("^ENOENT") then
      pcall(uv.fs_unlink, lock)
    end
    return
  end
  local content = uv.fs_read(fd, 128, 0)
  uv.fs_close(fd)
  if content == nil or content == token then
    pcall(uv.fs_unlink, lock)
  end
end

---@generic R
---@param path string
---@param fn fun(): R, string|nil, table|nil
---@param opts? Lib.Fs.WithLockOpts
---@return R|nil result
---@return string|nil err
---@return table|nil info  # `{ code = "locked"|"lock_stuck"|"io", retryable = boolean, lock = string }` for a failed lock (`lock` is `""` when `path` names no file), else what `fn` gave
return function(path, fn, opts)
  opts = opts or {}
  local create = opts.create_exclusive or create_exclusive
  local slashed = unify_slashes(path)
  local name = slashed:match("([^/]+)$")
  if not name then
    -- a folder path ("dir/sub/") or "": nothing to name the lock after, and a made-up name would create folders
    return nil,
      ("cannot lock %s: the path names no file"):format(path),
      { code = "io", retryable = false, lock = "" }
  end
  local dir = slashed:match("^(.*)/[^/]*$") or "."
  local lock = dir .. "/." .. name .. ".lock"
  local deadline = uv.hrtime() + (opts.wait_ms or 2000) * 1000000
  local stale_s = opts.stale_s or 10
  -- the pid, then a token no other acquisition has: what the release looks for before it deletes the file
  local token = ("%d\n%.0f"):format(uv.os_getpid(), uv.hrtime())
  while true do
    local ok, err = create(lock, token)
    if ok then
      break
    end
    local exists, transient = contention(err)
    if not transient then
      return nil,
        ("cannot lock %s: %s"):format(path, tostring(err)),
        { code = "io", retryable = false, lock = lock }
    end
    local stuck = ("%s has a lock that cannot be taken over: remove it by hand (%s)"):format(
      path,
      lock
    )
    if exists then
      local st = uv.fs_lstat(lock)
      -- a folder or a link where the lock file should be (a checked-in `.<name>.lock/`): nobody will ever release it
      if st and st.type ~= "file" then
        return nil, stuck, { code = "lock_stuck", retryable = false, lock = lock }
      end
      if st and os.time() - st.mtime.sec > stale_s then
        take_over(lock, stale_s)
      end
    end
    -- the deadline applies on EVERY turn: a stale lock that cannot be deleted must not spin the editor
    if uv.hrtime() > deadline then
      local st = uv.fs_lstat(lock)
      if not exists and st == nil then
        -- nothing occupies the name, yet the create is still refused (EPERM / EACCES / EBUSY on Windows): a
        -- permission problem (read-only folder, ACL), not a writer, and asking again will not help. (Measured on
        -- NTFS with POSIX delete semantics: a deleted name is gone at once, and a file that a foreign handle
        -- keeps from being deleted still shows as a file, so neither lands here.)
        return nil,
          ("cannot lock %s: %s"):format(path, tostring(err)),
          { code = "io", retryable = false, lock = lock }
      end
      if st and os.time() - st.mtime.sec > stale_s then
        -- older than the takeover age and still there: deleting it failed, and waiting longer will not change that
        return nil, stuck, { code = "lock_stuck", retryable = false, lock = lock }
      end
      return nil,
        ("%s is being written by another process (%s: %s)"):format(path, lock, tostring(err)),
        { code = "locked", retryable = true, lock = lock }
    end
    vim.wait(10)
  end
  local ran, res, res2, res3 = pcall(fn)
  release(lock, token)
  if not ran then
    error(res, 0)
  end
  return res, res2, res3
end
