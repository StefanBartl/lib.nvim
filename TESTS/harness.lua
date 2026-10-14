-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.
--
-- This runner and this helper are lib.nvim's own and stay that way (decision of
-- 2026-10-06, testing.nvim "Bootstrap circle", option A). testing.nvim depends on
-- lib.nvim, so if lib.nvim's tests ran on testing.nvim only, a bug in `error`,
-- `async`, `fs` or `system` -- modules testing.nvim itself uses -- could hide behind
-- the very runner that is broken by it. Nothing in TESTS/ imports testing.nvim.
-- testing.nvim's CI additionally runs this whole suite through its own runner on
-- three systems (job `lib-suite`), as a cross-check, not as a replacement.
-- The legacy sentinel `LIB_TESTS_OK` (last line of a green TESTS/run.lua run) stays.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then
    error(("FAIL %s: expected truthy, got %s"):format(msg or "", vim.inspect(v)), 2)
  end
end

---A case that cannot run on this host (a git that peels every tag level, no POSIX shell) says so: one line in the
---run's output, not a silently missing block. Not an assertion: a skipped case proves nothing.
---@param what string The case that was left out.
---@param reason string Why.
function H.skipped(what, reason)
  -- stderr with an explicit newline: `print` leaves the newline pending, so the line would glue onto the next one in
  -- a merged stream; stdout would corrupt `--events -`
  io.stderr:write(("[SKIPPED] %s: %s\n"):format(what, reason))
end

--- Create a fresh temp file path (not created on disk).
---@param suffix string|nil
---@return string
function H.tmpfile(suffix)
  return vim.fn.tempname() .. (suffix or ".tmp")
end

--- Read all lines of a file into an array (empty array if missing).
---@param path string
---@return string[]
function H.read_lines(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    out[#out + 1] = line
  end
  f:close()
  return out
end

--- Run `fn` with `target[key]` replaced by `value`, restoring the original
--- afterwards whatever happens inside `fn` -- including a raised assertion. A
--- bare "patch, call, restore" sequence skips the restore when `fn` raises,
--- leaving the replacement in place for the rest of the shared test run
--- (`TESTS/run.lua` loads every spec into one Neovim instance). The error is
--- re-raised unchanged: `error(err, 0)` adds no position, where `assert(ok, err)`
--- put "TESTS/harness.lua:NN:" in front of every failure message of every user.
---@param target table
---@param key any
---@param value any
---@param fn fun(): nil
function H.with_patched(target, key, value, fn)
  local orig = target[key]
  target[key] = value
  local ok, err = pcall(fn)
  target[key] = orig
  if not ok then
    error(err, 0)
  end
end

--- Run `fn` with `stdpath("config")` answering `link`, restoring the real one
--- afterwards whatever happens -- a leaked stub would redirect every later
--- spec in the run. Previously duplicated verbatim in
--- `stdpath_config_root_spec.lua`, `dev_reload_spec.lua`, and
--- `polymorphic_rootresolver_spec.lua` (no drift between the three, but three
--- copies of one small helper is exactly the kind of thing that only takes
--- one edit to the wrong copy to break).
---@param link string
---@param fn fun(): nil
function H.with_stdpath_config(link, fn)
  local orig = vim.fn.stdpath
  H.with_patched(vim.fn, "stdpath", function(what)
    if what == "config" then
      return link
    end
    return orig(what)
  end, fn)
end

return H
