---@module 'lib.nvim.fs.write.append'
--- Append `content` to a file, creating parent directories as needed.
---
--- Sibling of `lib.nvim.fs.write.to_file`, which truncates (`"w"`); this opens
--- in append mode (`"a"`). A trailing newline is added when missing so callers
--- can append line-oriented records without tracking separators themselves.

---@param path string
---@param content string
---@return boolean ok
---@return string|nil err
return function(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir == "" then
    return false, "Invalid directory for path: " .. path
  end
  local ok_mkdir, err_mkdir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    return false, "mkdir failed: " .. tostring(err_mkdir)
  end
  -- Binary mode, matching to_file's fix: "a" is text mode, which on Windows
  -- silently rewrites every "\n" in `content` to "\r\n".
  local f, err = io.open(path, "ab")
  if not f then
    return false, "open failed: " .. (err or path)
  end
  if content ~= "" and not content:match("\n$") then
    content = content .. "\n"
  end
  -- Same as to_file: the flush error of a buffered write shows up on close.
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
