---@module 'lib.nvim.buffer.open_background'
--- Add a file to the buffer list without creating or focusing a window.
---
--- By default the content is also loaded (`bufadd` + `bufload`), mirroring
--- Neovim's own background-open idiom. Pass `opts.load = false` to only
--- register the buffer (`bufadd` + `buflisted`), matching plain `:badd`
--- semantics for callers that must not eagerly read the file (e.g. from
--- inside a terminal float where blocking I/O would be disruptive).

---@param path string Absolute or relative file path
---@param opts? { load?: boolean } `load` defaults to true
---@return boolean ok
---@return integer|string bufnr_or_err Buffer number on success, error message otherwise
return function(path, opts)
  opts = opts or {}
  local load = opts.load ~= false

  if type(path) ~= "string" or path == "" then
    return false, "invalid path"
  end

  local abs = vim.fn.fnamemodify(path, ":p")
  if vim.fn.filereadable(abs) ~= 1 then
    return false, "file not readable: " .. abs
  end

  local bufnr = vim.fn.bufadd(abs)

  if load then
    local ok = pcall(vim.fn.bufload, bufnr)
    if not ok then
      return false, "failed to load buffer: " .. abs
    end
  end

  pcall(function()
    vim.bo[bufnr].buflisted = true
  end)

  return true, bufnr
end
