---@module 'lib.nvim.fs.write.to_file'

---@param path string
---@param content string
---@return boolean,string|nil
return function (path, content)
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
  f:write(content)
  f:close()
  return true, nil
end
