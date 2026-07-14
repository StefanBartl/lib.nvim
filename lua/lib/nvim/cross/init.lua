---@module 'lib.nvim.cross'
---Cross-platform utilities for Neovim/Lua
---Provides platform detection, path normalization, and shell helpers

local M = {}

-- Platform Detection
M.is_windows = require("lib.nvim.cross.platform.is_windows")
M.is_wsl = require("lib.nvim.cross.platform.is_wsl")
M.is_macos = require("lib.nvim.cross.platform.is_macos")
M.is_linux = require("lib.nvim.cross.platform.is_linux")
M.is = require("lib.nvim.cross.platform.is")

-- Filesystem
M.fs = {
  cwd = require("lib.nvim.cross.fs._cwd"),
}

M.separators = {
  has_win_sep = require("lib.nvim.cross.fs.separators.has_win_sep"),
  normalize = require("lib.nvim.cross.fs.separators.normalize"),
  unify_slashes = require("lib.nvim.cross.fs.separators.unify_slashes"),
  collapse_dots = require("lib.nvim.cross.fs.separators.collapse_dots"),
  drive_upper = require("lib.nvim.cross.fs.separators.drive_upper"),
}

-- UV/Loop compatibility
M.uv = {
  spawn_command = require("lib.nvim.cross.uv.spawn_command"),
  spawn_shell_command = require("lib.nvim.cross.uv.spawn_shell_command"),
}

M.run = {
  shell = require("lib.nvim.cross.run").shell,
  run = require("lib.nvim.cross.run").run,
  run_blocking = require("lib.nvim.cross.run").run_blocking,
  run_argv = require("lib.nvim.cross.run_argv"),
}

return M
