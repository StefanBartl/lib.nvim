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
  local f, err = io.open(path, "a")
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
