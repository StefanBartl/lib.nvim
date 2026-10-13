---@module 'lib.nvim.fs.create_exclusive'
--- Create a file with some content, failing with `"exists"` when it is already there.
---
--- The existence test and the creation are ONE syscall (`O_CREAT|O_EXCL`), so two writers can never both believe
--- they created the same file. The parent directory is created first (`lib.nvim.fs.mkdirp`). Bytes are written as
--- given. A failed or short write removes the file again, so no half-written file is left that the next caller
--- would read as "exists".
---
--- Moved here from `tasks_nvim.fsio.create_exclusive` (tasks.nvim@921a0c4), where it is the claim of a new task
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
  local parent = unify_slashes(path):match("^(.*)/[^/]*$")
  if parent and parent ~= "" then
    local made, merr = mkdirp(parent)
    if not made then
      return false, tostring(merr)
    end
  end
  local fd, open_err = uv.fs_open(path, "wx", 420) -- 0644, less the umask
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
