---@module 'lib.nvim.fs.with_lock'
--- Run a function while holding an advisory lock on a path.
---
--- The lock is a hidden `.<name>.lock` file next to `path`, created exclusively (`lib.nvim.fs.create_exclusive`).
--- Every process that read-modify-writes the same file goes through it, so two of them (an agent's command line and
--- an editor plugin) never start from the same text and drop each other's change. It serialises the COOPERATING
--- writers only; an editor with the file open is not one of them.
---
--- A holder that died leaves its file behind: a lock older than `opts.stale_s` (10 s; a locked write takes
--- milliseconds) is taken over. Waiting is bounded (`opts.wait_ms`, 2 s), then `nil, err, info`.
---
--- `info.code` says why: `locked` (another process holds it right now; asking again can help, `retryable`),
--- `lock_stuck` (a lock that nobody will release: older than the takeover age and not deletable, or a folder or link
--- where the lock file should be; remove it by hand) or `io`. What `fn` answers (up to three values) is handed back;
--- an error of `fn` is raised again after the lock is released. The codes are those of `lib.nvim.contract.errors`.
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

local uv = vim.uv or vim.loop

---Whether the error of a create is contention and not a real failure. On Windows a lock that was unlinked a moment
---ago answers EPERM / EACCES / EBUSY to a create until the delete completes.
---@param err any
---@return boolean exists
---@return boolean transient
local function contention(err)
  local exists = create_exclusive.is_exists(err)
  local transient = exists
    or (
      type(err) == "string"
      and (
          err:find("EPERM", 1, true)
          or err:find("EACCES", 1, true)
          or err:find("EBUSY", 1, true)
        )
        ~= nil
    )
  return exists, transient
end

---@generic R
---@param path string
---@param fn fun(): R, string|nil, table|nil
---@param opts? Lib.Fs.WithLockOpts
---@return R|nil result
---@return string|nil err
---@return table|nil info  # `{ code = "locked"|"lock_stuck"|"io", retryable = boolean, lock = string }` for a failed lock, else what `fn` gave
return function(path, fn, opts)
  opts = opts or {}
  local create = opts.create_exclusive or create_exclusive
  local slashed = unify_slashes(path)
  local dir = slashed:match("^(.*)/[^/]*$") or "."
  local lock = dir .. "/." .. (path:match("([^/\\]+)$") or path) .. ".lock"
  local deadline = uv.hrtime() + (opts.wait_ms or 2000) * 1000000
  local stale_s = opts.stale_s or 10
  while true do
    local ok, err = create(lock, tostring(uv.os_getpid()))
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
        pcall(uv.fs_unlink, lock)
      end
    end
    -- the deadline applies on EVERY turn: a stale lock that cannot be deleted must not spin the editor
    if uv.hrtime() > deadline then
      local st = uv.fs_lstat(lock)
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
  pcall(uv.fs_unlink, lock)
  if not ran then
    error(res, 0)
  end
  return res, res2, res3
end
