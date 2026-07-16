---@module 'lib.nvim.normalize'
--- A small, dependency-free normalization toolkit for plugin configs.
--- Focus:
---   * Strict typing at the boundary (apply_* never writes nil into typed fields).
---   * Common coercions (int/float/bool/enum/string/list/path/severity/loglevel).
---   * Utilities for schema-driven config merging.
--- Notes:
---   * All functions are side-effect free except apply_* helpers which mutate the provided table.
---   * Neovim APIs are used when available (vim.fs.normalize, vim.uv); fall back gracefully.

local lazy = require("lib.lua.lazy")
---@type Lib.Normalize.Validators
local validators = lazy.require("lib.nvim.normalize.validators")
---@type Lib.Normalize.Utils
local utils = lazy.require("lib.nvim.normalize.utils")

local M = {}
-- =========================================================
-- Direct Value Normalizers (Pure Functions)
-- =========================================================
  M.to_bool = validators.to_bool
  M.to_int = validators.to_int
  M.to_float = validators.to_float
  M.to_string = validators.to_string
  M.to_enum = validators.to_enum
  M.to_string_list = validators.to_string_list
  M.to_argv = validators.to_argv
  M.to_diagnostic_severity = validators.to_diagnostic_severity
  M.to_log_level = validators.to_log_level
  M.to_path = validators.to_path
-- =========================================================
-- Validators with (ok, val, err) Pattern
-- =========================================================
  M.as_int = validators.as_int
  M.as_bool = validators.as_bool
  M.is_one_of = validators.is_one_of
  M.buf_valid = validators.buf_valid
  M.win_valid = validators.win_valid
-- =========================================================
-- Utility Fuctions
-- =========================================================
  M.trim = utils.trim
  M.clamp = utils.clamp
  M.coalesce = utils.coalesce
  M.path_kind = utils.path_kind
  M.normalize_path = utils.normalize_path
  M.dedup_strings = utils.dedup_strings

---@type Lib.Normalize
return M
