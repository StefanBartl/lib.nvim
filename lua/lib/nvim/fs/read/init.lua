---@module 'lib.nvim.fs.read'
--- Read the whole contents of a file at `path` into a string.
---
--- The read-side counterpart to `lib.nvim.fs.write.to_file`: pure filesystem
--- side effect only, no `notify`, mirrors its error-message style inverted.
---
---```lua
--- local read = require("lib.nvim.fs.read")
--- local content, err = read("/repo/README.md")
--- if not content then
---   vim.notify(err, vim.log.levels.ERROR)
--- end
---```

---@param path string
---@return string|nil content
---@return string|nil err
return function(path)
  local f, open_err = io.open(path, "r")
  if not f then
    return nil, "open failed: " .. (open_err or path)
  end

  local ok, content_or_err = pcall(function()
    return f:read("*a")
  end)
  f:close()

  if not ok then
    return nil, "read failed: " .. tostring(content_or_err)
  end

  if content_or_err == nil then
    return nil, "read failed: " .. path
  end

  return content_or_err, nil
end
