-- scripts/regen_data_classes_cases.lua -- rewrite TESTS/fixtures/data_classes_cases.json from tasks-desktop
--
-- Runs the dump of a tasks-desktop checkout (ui/web/classes-cases-dump.mjs, needs node) on the case list as committed
-- at its HEAD and writes the fixture (one case per line) and its sidecar (source commit, case count, sha256). From the
-- repo root:
--
--   nvim -n -i NONE --headless -u NONE -l scripts/regen_data_classes_cases.lua [--force] [tasks-desktop dir]
--
-- The directory defaults to `TASKS_DESKTOP_DIR`, else a sibling `tasks-desktop`. Uncommitted changes in the checkout
-- are ignored (the sidecar names HEAD, so the fixture is what HEAD dumps). A checkout that does not contain the
-- commit of the current sidecar (older, or on a diverged branch) is refused, since it would silently take the fixture
-- back to an older list; `--force` overrides that.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local cases_mod = dofile(vim.fs.joinpath(root, "TESTS", "support", "data_classes_cases.lua"))

local force, dir = false, nil
for _, a in ipairs(_G.arg or {}) do
  if a == "--force" then
    force = true
  elseif dir == nil and a ~= "" then
    dir = a
  else
    io.stderr:write("regen_data_classes_cases: unexpected argument " .. a .. "\n")
    os.exit(2)
  end
end
if dir == nil then
  dir = cases_mod.checkout_dir()
end
dir = vim.fn.fnamemodify(dir, ":p"):gsub("[\\/]$", "")

local ok, message = cases_mod.regenerate(dir, { force = force })
if not ok then
  io.stderr:write("regen_data_classes_cases: " .. message .. "\n")
  os.exit(1)
end
io.stdout:write(message .. "\n")
