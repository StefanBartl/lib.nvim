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

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

local specs = {
  "logger_spec.lua",
  "autocmd_spec.lua",
  "run_argv_spec.lua",
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
  "composer_spec.lua",
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
