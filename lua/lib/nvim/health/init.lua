---@module 'lib.nvim.health'
--- Small helpers for writing a plugin's own `:checkhealth` implementation.
---@description
--- `version_ok`: extracted from **three** copies of the same six lines
--- checking `vim.version()` against a `{major, minor, patch}` floor — this
--- repo's own `lib.health`, documentation.nvim, and runtime-analysis.nvim.
---
--- `check_require`: extracted from **two** byte-identical copies (dap.nvim,
--- debugging.nvim) that each reported one required module through
--- `vim.health.{ok,warn,info}`.

local M = {}

---Whether the running Neovim is at least `min` = `{major, minor, patch}`.
---@param min integer[]
---@return boolean
function M.version_ok(min)
  local v = vim.version()
  if v.major ~= min[1] then
    return v.major > min[1]
  end
  if v.minor ~= min[2] then
    return v.minor > min[2]
  end
  return v.patch >= min[3]
end

---Report whether `mod` can be `require`d, through `vim.health`.
---@param mod string                   module path to probe with `require`
---@param label string                 human-readable name shown in the report
---@param level "ok"|"warn"|"info"     how loud a missing module should be
---@return nil
function M.check_require(mod, label, level)
  if pcall(require, mod) then
    vim.health.ok(label .. " (" .. mod .. ")")
  elseif level == "warn" then
    vim.health.warn(label .. " missing (" .. mod .. ")")
  else
    vim.health.info(label .. " not found (" .. mod .. ")")
  end
end

---@type Lib.Nvim.Health
return M
