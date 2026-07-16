---@module 'lib.nvim.buf_win_tab.get_option'
--- Read a buffer option across a wide range of Neovim versions.
---
--- Neovim moved buffer-option access from `nvim_buf_get_option` to
--- `nvim_get_option_value` and deprecated the former; older builds lack the
--- latter. This tries every known route, each guarded by `pcall`, and returns
--- the first value it can get — so callers stop caring which build they run on.
---
---   local ft = require("lib.nvim.buf_win_tab.get_option")(bufnr, "filetype")

require("lib.nvim.buf_win_tab.get_option.@types")

---@param bufnr integer
---@param name string Option name, e.g. "filetype"
---@return any|nil value `nil` when every access route fails
return function(bufnr, name)
  -- 1) Modern API (Neovim >= 0.8).
  local ok, value = pcall(vim.api.nvim_get_option_value, name, { buf = bufnr })
  if ok then
    return value
  end

  -- 2) Deprecated but broadly compatible.
  ok, value = pcall(vim.api.nvim_buf_get_option, bufnr, name)
  if ok then
    return value
  end

  -- 3) Current buffer shortcut.
  local ok_cur, cur = pcall(vim.api.nvim_get_current_buf)
  if ok_cur and cur == bufnr then
    ok, value = pcall(function()
      return vim.bo[name]
    end)
    if ok then
      return value
    end
  end

  -- 4) Evaluate `vim.bo` from inside the buffer's own context.
  ok, value = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.bo[name]
  end)
  if ok then
    return value
  end

  return nil
end
