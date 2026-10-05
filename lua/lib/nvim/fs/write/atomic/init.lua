---@module 'lib.nvim.fs.write.atomic'
--- Byte-exact atomic write: a sibling temp file, flushed, then renamed over the target.
---
--- Unlike `lib.nvim.fs.write.to_file` it appends nothing (a file whose body does not end in a newline stays that
--- way), and unlike a plain `io.open(path, "wb")` a crash leaves the old or the new content, never an empty file.
--- The temp file takes over the mode of the file it replaces (a private `0600` file does not become `0644`) and is
--- removed again when any step fails.

local uv = vim.uv or vim.loop

---@class Lib.Fs.AtomicOpts
---@field mkdirp? boolean  Create the parent directory first (default false).
---@field tag? string      Infix of the temp name `<path>.<tag>.<pid>.<hrtime>` (default "atomic-tmp").

---@param path string
---@param content string
---@param opts? Lib.Fs.AtomicOpts
---@return boolean ok
---@return string|nil err
return function(path, content, opts)
  opts = opts or {}
  if type(path) ~= "string" or path == "" or type(content) ~= "string" then
    return false, "write_atomic needs a path and a string"
  end
  if opts.mkdirp then
    local made, merr = pcall(vim.fn.mkdir, vim.fn.fnamemodify(path, ":h"), "p")
    if not made then
      return false, "mkdir failed: " .. tostring(merr)
    end
  end
  -- Unique per process and call, so concurrent writers never share a temp file.
  local tmp = ("%s.%s.%d.%d"):format(path, opts.tag or "atomic-tmp", uv.os_getpid(), uv.hrtime())
  local fd, open_err = uv.fs_open(tmp, "wx", 420) -- 0644, less the umask
  if not fd then
    return false, "open failed: " .. tostring(open_err or tmp)
  end
  local wrote, write_err = uv.fs_write(fd, content, 0)
  if wrote then
    local old = uv.fs_stat(path)
    if old then
      pcall(uv.fs_fchmod, fd, old.mode % 4096)
    end
    -- Best effort: a file system that cannot sync (some network shares) still gets its bytes.
    pcall(uv.fs_fsync, fd)
  end
  local closed, close_err = uv.fs_close(fd)
  if not wrote or wrote ~= #content or not closed then
    pcall(os.remove, tmp)
    return false, "write failed: " .. tostring(write_err or close_err or tmp)
  end
  local renamed, rename_err = require("lib.nvim.cross.fs.mutate").rename_file(tmp, path)
  if not renamed then
    pcall(os.remove, tmp)
    return false, "rename failed: " .. tostring(rename_err)
  end
  return true, nil
end
