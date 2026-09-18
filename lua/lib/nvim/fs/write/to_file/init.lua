---@module 'lib.nvim.fs.write.to_file'
--- Synchronous, byte-exact file write: creates parent directories and
--- appends a trailing newline if the content doesn't already end with one.

---@param path string
---@param content string
---@return boolean,string|nil
return function(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir == "" then
    return false, "Invalid directory for path: " .. path
  end
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    return false, "mkdir failed: " .. tostring(err_mkdir)
  end
  -- Binary mode: ("w" is text mode, which on Windows silently rewrites
  -- every "\n" in `content` to "\r\n" — Lua's io library, unlike libuv's
  -- raw fs_write used by fs.write.async, honors the host platform's text
  -- translation by default.) Writes must be byte-exact and consistent
  -- across platforms, matching the async counterpart.
  local f, err = io.open(path, "wb")
  if not f then
    return false, "open failed: " .. (err or path)
  end
  if content ~= "" and not content:match("\n$") then
    content = content .. "\n"
  end
  -- Writes are buffered: a full disk or a read-only mount usually surfaces
  -- on close, not on write, so both results are checked before claiming
  -- the bytes are on disk.
  local ok_write, write_err = f:write(content)
  local ok_close, close_err = f:close()
  if not ok_write then
    return false, "write failed: " .. tostring(write_err or path)
  end
  if not ok_close then
    return false, "close failed: " .. tostring(close_err or path)
  end
  return true, nil
end
