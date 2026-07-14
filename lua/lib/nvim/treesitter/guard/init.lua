---@module 'lib.nvim.treesitter.guard'
--- Filetype allowlist gate for treesitter-dependent features (highlighting,
--- foldexpr, indentexpr). This is **not** a parser-availability probe — it's
--- a curated list of filetypes considered safe/desired for treesitter
--- activation, independent of whether a parser happens to be installed.

require("lib.nvim.treesitter.guard.@types")

local M = {}

---Default filetype allowlist.
---@type table<string, boolean>
M.DEFAULT_WHITELIST = {
  lua = true,
  vim = true,
  vimdoc = true,

  bash = true,
  zsh = true,

  javascript = true,
  typescript = true,
  tsx = true,

  go = true,
  rust = true,
  python = true,
  c = true,
  cpp = true,

  json = true,
  yaml = true,
  toml = true,
  markdown = true,
}

---Check whether treesitter should be enabled for a buffer.
---@param bufnr integer
---@param whitelist? table<string, boolean> Defaults to `M.DEFAULT_WHITELIST`
---@return boolean
function M.is_enabled(bufnr, whitelist)
  if not bufnr or bufnr == 0 then
    return false
  end

  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    return false
  end

  return (whitelist or M.DEFAULT_WHITELIST)[ft] == true
end

return M
