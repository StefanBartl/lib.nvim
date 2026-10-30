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
--- - It is keyed by the file the path RESOLVES to (`fs_realpath`): a symlink to the file, a symlinked folder, `..`
---   segments, another case of an existing name on a case-insensitive disk take the same lock, beside the real file.
---   A HARD link is a second name without a resolution to the first and takes another lock; so does a name that
---   does not exist yet spelled in another case. (`tasks_nvim.fsio.with_lock` of tasks.nvim@6bc8d99 keys by the
---   spelling: switch all writers of a file at once, never run both side by side on a symlinked path.)
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
--- (up to three values) is handed back; an error of `fn` is raised again after the lock is released. A `path` that is
--- not a string or holds a NUL byte (libuv would cut it there) is an `io` failure with `info.lock = ""`. The codes are
--- those of `lib.nvim.contract.errors`.
---
--- Moved here from `tasks_nvim.fsio.with_lock` (tasks.nvim@6bc8d99). Not to be confused with
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

---Folder and name of `slashed` (forward slashes, names a file).
---@param slashed string
---@return string dir
---@return string name
local function split(slashed)
  return slashed:match("^(.*)/[^/]*$") or ".", slashed:match("([^/]+)$")
end

---The lock file of a path. It is keyed by the file the path RESOLVES to (`fs_realpath`), not by its spelling: a
---symlink to the file, a symlinked folder, `..` segments, another case of the name on a case-insensitive disk or an
---8.3 short name all take the same lock. A file that does not exist yet (or a dangling link) is keyed by the resolved
---folder and the name as given; a folder that does not exist yet by the spelling (it is made by the create).
---@param slashed string
---@return string
local function lock_path(slashed)
  local real = uv.fs_realpath(slashed)
  if real then
    local dir, name = split(unify_slashes(real))
    if name then
      return dir .. "/." .. name .. ".lock"
    end
  end
  local dir, name = split(slashed)
  local real_dir = uv.fs_realpath(dir)
  return (real_dir and unify_slashes(real_dir):gsub("/$", "") or dir) .. "/." .. name .. ".lock"
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
  if type(path) ~= "string" or path:find("\0", 1, true) then
    -- libuv cuts a path at its first NUL: the lock would be made for (and the caller would write) another file
    return nil,
      ("cannot lock %s: invalid arguments: path must be a string without NUL bytes"):format(
        type(path) == "string" and ("%q"):format(path) or tostring(path)
      ),
      { code = "io", retryable = false, lock = "" }
  end
  local slashed = unify_slashes(path)
  if not slashed:match("([^/]+)$") then
    -- a folder path ("dir/sub/") or "": nothing to name the lock after, and a made-up name would create folders
    return nil,
      ("cannot lock %s: the path names no file"):format(path),
      { code = "io", retryable = false, lock = "" }
  end
  local lock = lock_path(slashed)
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
