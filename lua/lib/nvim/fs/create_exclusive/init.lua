---@module 'lib.nvim.fs.create_exclusive'
--- Create a file with some content, failing with `"exists"` when it is already there.
---
--- The exclusive open (`O_CREAT|O_EXCL`) is the atomic part, so two writers can never both believe they created the
--- same file. A name that is taken by anything counts as present, a symlink included (a dangling one too): it is
--- looked up with an `lstat` first, because on Windows `O_EXCL` follows a dangling link and would create the file
--- (or a folder) at the link TARGET, outside the folder. A missing parent directory is created
--- (`lib.nvim.fs.mkdirp`) when the open answers `ENOENT`, not before every call. Bytes are written as given. A failed or short write removes the file again, so no
--- half-written file is left that the next caller would read as "exists".
---
--- It never raises: a `path` or `content` that is not a string, a `path` with a NUL byte (libuv would cut it there
--- and create another file) and a `path` that names a folder (ends in a
--- slash), are answered as an error before anything is created.
---
--- Moved here from `tasks_nvim.fsio.create_exclusive` (tasks.nvim@6bc8d99), where it is the claim of a new task
--- file and the lock file of `lib.nvim.fs.with_lock`.
---
---```lua
--- local create = require("lib.nvim.fs.create_exclusive")
--- local ok, err = create(dir .. "/new.md", "text")
--- if not ok and create.is_exists(err) then
---   -- somebody else was first
--- end
---```

require("lib.nvim.fs.create_exclusive.@types")

local mkdirp = require("lib.nvim.fs.mkdirp")
local unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes")

local uv = vim.uv or vim.loop

---The error the call answers when the file was already there. Compare through `is_exists`, not against the word.
local EXISTS = "exists"

---@param err any
---@return boolean
local function is_exists(err)
  return err == EXISTS
end

---@param path string
---@param content string
---@return boolean ok
---@return string|nil err  `"exists"` when the file was already present
local function create_exclusive(path, content)
  -- checked before anything is created: a non-string content would raise after the file exists, skipping the
  -- close and the cleanup, and leave a permanent "exists" claim behind
  if type(path) ~= "string" or type(content) ~= "string" then
    return false, "invalid arguments: path and content must be strings"
  end
  if path:find("\0", 1, true) then
    -- libuv cuts a path at its first NUL: the file made would be another one than the caller named
    return false, "invalid arguments: the path holds a NUL byte: " .. ("%q"):format(path)
  end
  local slashed = unify_slashes(path)
  if slashed:sub(-1) == "/" then
    -- no file name: the parent would be the folder with the file's name, made by mkdirp and then answered "exists"
    return false, "open failed: the path names a folder, not a file: " .. path
  end
  -- POSIX O_EXCL refuses a name that is a symlink, even a dangling one; Windows follows it and creates (or fails
  -- on) the link TARGET, outside the folder. Any existing name, link included, counts as present on every platform.
  if uv.fs_lstat(path) then
    return false, EXISTS
  end
  local fd, open_err = uv.fs_open(path, "wx", 420) -- 0644, less the umask
  local parent = slashed:match("^(.*)/[^/]*$")
  if not fd and parent and parent ~= "" and tostring(open_err):match("^ENOENT") then
    -- The parent folder is missing: only now is it made. Walking the whole chain first costs about six times the
    -- create itself, on every call, and `with_lock` retries a contended lock every 10 ms.
    local made, merr = mkdirp(parent)
    if not made then
      return false, tostring(merr)
    end
    if uv.fs_lstat(path) then -- (made by somebody else meanwhile, a link included: see above)
      return false, EXISTS
    end
    fd, open_err = uv.fs_open(path, "wx", 420)
  end
  if not fd then
    if tostring(open_err):match("^EEXIST") then
      return false, EXISTS
    end
    return false, "open failed: " .. tostring(open_err)
  end
  local written, write_err = uv.fs_write(fd, content, 0)
  uv.fs_close(fd)
  if not written or written ~= #content then
    pcall(uv.fs_unlink, path)
    return false, "write failed: " .. tostring(write_err or path)
  end
  return true, nil
end

---@type Lib.Fs.CreateExclusive
return setmetatable({ EXISTS = EXISTS, is_exists = is_exists }, {
  __call = function(_, path, content)
    return create_exclusive(path, content)
  end,
})
