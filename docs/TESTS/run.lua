-- docs/TESTS/run.lua — headless test runner for lib.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile docs/TESTS/run.lua" -c "qa!"
-- or:
--   nvim --headless -u NONE -l docs/TESTS/run.lua
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero on the first failing spec.

-- Make the repo importable whether invoked via -l (cwd) or luafile.
vim.opt.rtp:append(vim.fn.getcwd())

-- runtime-analysis.nvim is a runtime dependency of telemetry_wrap_spec.lua
-- only (the thin caller instrumenting `require("lib")` now lives there) —
-- the same three-candidate search runtime-analysis.nvim's own run.lua uses
-- to find lib.nvim, mirrored back. Not fatal if missing: that one spec fails
-- with a clear `require` error rather than the whole runner refusing to start.
local function add_runtime_analysis()
  if pcall(require, "runtime-analysis.telemetry") then
    return
  end
  local candidates = {}
  if vim.env.RUNTIME_ANALYSIS_DIR and vim.env.RUNTIME_ANALYSIS_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.RUNTIME_ANALYSIS_DIR
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/runtime-analysis.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/runtime-analysis.nvim"
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.rtp:append(dir)
      if pcall(require, "runtime-analysis.telemetry") then
        return
      end
    end
  end
end

add_runtime_analysis()

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

local specs = {
  "polymorphic_rootresolver_spec.lua",
  "logger_spec.lua",
  "autocmd_spec.lua",
  "autocmd_dispatcher_spec.lua",
  "run_argv_spec.lua",
  "run_spec.lua",
  "spawn_env_spec.lua",
  "async_spec.lua",
  "async_walk_spec.lua",
  "wslpath_spec.lua",
  "system_job_spec.lua",
  "ui_kit_spec.lua",
  "statusline_spec.lua",
  "lua_helpers_spec.lua",
  "nvim_helpers_spec.lua",
  "window_spec.lua",
  "context_spec.lua",
  "cache_spec.lua",
  "cwd_spec.lua",
  "project_store_spec.lua",
  "harvest_spec.lua",
  "mutate_spec.lua",
  "lock_spec.lua",
  "neotree_watch_spec.lua",
  "watch_spec.lua",
  "composer_spec.lua",
  "telemetry_wrap_spec.lua",
  "git_spec.lua",
  "curl_spec.lua",
  "deps_spec.lua",
}

--- Straight to stdout rather than through `print`.
---
--- `print` in a headless Neovim goes through the message area, and a spec that
--- opens a window forces a redraw that swallows the pending newline — two spec
--- results then run together on one line, which is exactly as confusing as it
--- sounds when a run is being read for a failure. A headless runner's output
--- is meant to be read by a person or a log, not rendered in a UI.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nLIB_TESTS_OK")
