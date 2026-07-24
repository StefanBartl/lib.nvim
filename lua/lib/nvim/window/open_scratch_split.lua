---@module 'lib.nvim.window.open_scratch_split'
--- Open a fresh scratch buffer in a plain split (not floating). Every call
--- opens its own new window — unlike `open_named_scratch`, there is no
--- de-duplication by buffer name, which is the right behaviour for
--- report/audit-style output where a second invocation is expected to
--- produce its own buffer rather than silently overwrite a previous run.
--- Complements `make_scratch` (floating) and `open_named_scratch` (named,
--- de-duplicated split).

local api = vim.api

---@param lines? string[] Initial buffer content
---@param opts? Lib.Window.OpenScratchSplitOpts
---@return integer bufnr
---@return integer winid
return function(lines, opts)
  opts = opts or {}

  local cmd
  if opts.split == "above" then
    cmd = "aboveleft new"
  elseif opts.split == "below" then
    cmd = "belowright new"
  elseif opts.split == "left" then
    cmd = "aboveleft vnew"
  elseif opts.split == "right" then
    cmd = "belowright vnew"
  else
    -- No direction requested: plain `:new`, honoring the user's own
    -- 'splitbelow'/'splitright' settings instead of overriding them.
    cmd = "new"
  end
  vim.cmd(cmd)

  local winid = api.nvim_get_current_win()
  local bufnr = api.nvim_get_current_buf()

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  if opts.filetype ~= nil then
    vim.bo[bufnr].filetype = opts.filetype
  end
  if lines ~= nil then
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  vim.bo[bufnr].modifiable = opts.modifiable == true

  return bufnr, winid
end
