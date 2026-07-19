---@module 'lib.nvim.cross.executable'
--- Executable lookup helpers: PATH resolution and Mason-managed binaries.
---
--- Consolidates a pattern independently re-implemented in several plugins
--- (open.nvim's `util.find_exec`, dap.nvim's `utils.executable`): "is this
--- on PATH", "which of these candidates is", and "resolve a Mason-installed
--- binary's path, accounting for the .cmd suffix Mason uses on Windows".

local M = {}

---True when `name` is found on PATH.
---@param name string
---@return boolean
function M.exists(name)
  return vim.fn.executable(name) == 1
end

---Absolute path to `name` if it is on PATH, else nil.
---@param name string
---@return string|nil
function M.path(name)
  local exe = vim.fn.exepath(name)
  return (exe ~= "" and exe) or nil
end

---Return the first executable found on PATH from a single name or a list
---of candidate names, or nil if none are found.
---@param name_or_candidates string|string[]
---@return string|nil
function M.find(name_or_candidates)
  if type(name_or_candidates) == "string" then
    return M.exists(name_or_candidates) and name_or_candidates or nil
  end
  for _, name in ipairs(name_or_candidates) do
    if M.exists(name) then
      return name
    end
  end
  return nil
end

---Resolve a Mason-managed binary's path (`stdpath("data")/mason/bin/<name>`,
---with a `.cmd` suffix on native Windows), or nil if it isn't installed.
---@param package_name string
---@return string|nil
function M.mason_bin(package_name)
  local bin = vim.fn.stdpath("data") .. "/mason/bin/" .. package_name
  if require("lib.nvim.cross.platform.is_windows")() then
    bin = bin .. ".cmd"
  end

  local uv = vim.uv or vim.loop
  local ok, stat = pcall(uv.fs_stat, bin)
  if ok and stat then
    return bin
  end
  return nil
end

return M
