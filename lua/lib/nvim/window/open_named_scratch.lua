---@module 'lib.nvim.window.open_named_scratch'
--- Find-or-replace a named scratch buffer shown in a split (not a float).
--- Complements `make_scratch` (which always opens a floating window): this
--- is for plugins that want a dedicated, de-duplicated split — e.g. a log
--- viewer or a list view — identified by a stable buffer name so a second
--- call reuses the same buffer/window instead of piling up duplicates.

---@param name string Unique buffer name (e.g. "MyPlugin://log")
---@param lines? string[] Initial buffer content
---@param opts? { filetype?: string, split?: "above"|"below"|"left"|"right", size?: integer, modifiable?: boolean }
---@return integer bufnr
---@return integer winid
return function(name, lines, opts)
  opts = opts or {}

  local existing_bufnr = vim.fn.bufnr(name)
  local bufnr
  if existing_bufnr ~= -1 and vim.api.nvim_buf_is_valid(existing_bufnr) then
    bufnr = existing_bufnr
  else
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
  end

  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end

  vim.bo[bufnr].modifiable = true
  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  vim.bo[bufnr].modifiable = opts.modifiable ~= false

  -- Find an existing window already showing this buffer (any tab-visible window).
  local winid
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      winid = w
      break
    end
  end

  if not winid then
    local split = opts.split or "below"
    local cmd = ({
      above = "aboveleft split",
      below = "belowright split",
      left = "aboveleft vsplit",
      right = "belowright vsplit",
    })[split] or "belowright split"
    vim.cmd(cmd)
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    if opts.size then
      if split == "left" or split == "right" then
        vim.api.nvim_win_set_width(winid, opts.size)
      else
        vim.api.nvim_win_set_height(winid, opts.size)
      end
    end
  else
    vim.api.nvim_set_current_win(winid)
  end

  return bufnr, winid
end
