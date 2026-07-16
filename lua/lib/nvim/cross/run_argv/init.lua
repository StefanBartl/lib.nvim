---@module 'lib.nvim.cross.run_argv'
--- Low-level argv-based process runner with stdin support.

local M = {}

---@param cmd string[]
---@param input? string
---@return boolean, string|nil
function M.run_blocking(cmd, input)
  -- vim.system path (Neovim ≥0.10)
  if vim.system then
    local res = vim.system(cmd, { text = true, stdin = input }):wait()
    if res.code == 0 then
      return true, nil
    end
    return false, (res.stderr ~= "" and res.stderr) or ("exit code " .. res.code)
  end

  -- Legacy fallback
  local out = vim.fn.system(cmd, input or "")
  if vim.v.shell_error == 0 then
    return true, nil
  end
  return false, out
end

--- Like `run_blocking`, but also returns captured stdout on success — the
--- gap `run_blocking` deliberately leaves open (it was designed for
--- "run this and tell me if it worked", not "run this and give me its
--- output"). Mirrors the legacy `local out = vim.fn.system(cmd)` +
--- `vim.v.shell_error` idiom, just via `vim.system` (no shell) when available.
---@param cmd string[]
---@param input? string
---@return boolean ok
---@return string output Captured stdout, both on success and failure
function M.run_blocking_captured(cmd, input)
  if vim.system then
    local res = vim.system(cmd, { text = true, stdin = input }):wait()
    return res.code == 0, res.stdout or ""
  end

  local out = vim.fn.system(cmd, input or "")
  return vim.v.shell_error == 0, out
end

return M
