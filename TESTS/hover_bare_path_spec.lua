-- TESTS/hover_bare_path_spec.lua — what text on a line is allowed to open a
-- hover, and — the part that actually goes wrong — what a *non-existent*
-- target is allowed to be reported as broken.
--
-- The framework's own doc puts it as "a missing path is reported only when it
-- cannot have been anything else". Getting that wrong is not a quiet bug: a
-- false positive is a red ✗ float asserting a file is missing that nobody
-- ever claimed existed, over ordinary prose. The separator alone used to be
-- the whole test, and prose writes separators constantly — `and/or`, a table
-- header `Actual/Insgesamt`, a ratio `60% / 27%`, a word given a trailing
-- slash (`sortiert/`). Each of those is pinned below.
--
-- Driven through a real window, cursor and `<cfile>`, because `<cfile>` is
-- half the logic: what counts as one token is `'isfname'`, which is pinned
-- here so the same line yields the same token on every platform.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local api = vim.api
  local bare = require("lib.nvim.hover.bare_path")

  -- A directory that really exists, so the "resolved" case is a real stat
  -- rather than a fixture pretending to be one.
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/docs", "p")
  vim.fn.writefile({ "# real" }, root .. "/docs/real.md")

  local win = api.nvim_get_current_win()
  local prev_buf = api.nvim_win_get_buf(win)
  local prev_isfname = vim.o.isfname
  vim.o.isfname = "@,48-57,/,.,-,_,+,,,#,$,%,~,=,:"

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, root .. "/notes.md")
  api.nvim_win_set_buf(win, buf)

  --- The target reported with the cursor parked on `marker` inside `line`.
  ---@param line string
  ---@param marker string substring of `line` to put the cursor on
  ---@return string|nil
  local function target(line, marker)
    api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    local at = line:find(marker, 1, true)
    ok(at ~= nil, ("marker %q is in %q"):format(marker, line))
    api.nvim_win_set_cursor(win, { 1, at - 1 })
    local src = bare.under_cursor(buf)
    return src and src.target or nil
  end

  --- Nothing at all is reported for this position.
  ---@param line string
  ---@param marker string
  ---@param msg string
  local function silent(line, marker, msg)
    eq(target(line, marker), nil, msg)
  end

  -- ── The regressions: prose that carries a separator and means nothing ───
  -- All four opened a "✗ no such file" float for a directory nobody named.
  silent("wenn man zb sortiert/ schreibt", "sortiert/", "a word with a trailing slash is a word")
  silent("| --% | /--% |", "/--%", "a punctuation-only token has no name in it")
  silent("| 60% / 27% |", "/ 2", "a ratio's slash is not a root")
  silent("use and/or here", "and/or", "prose writes `and/or`, not a directory")
  silent("| Actual/Insgesamt |", "Actual/", "…nor is a two-word table header a path")

  -- The rule that predates all of this, restated so a future loosening of the
  -- test above cannot quietly take it with it: a bare `name.ext` is how every
  -- Lua module is spelled, so it stays silent when it resolves to nothing.
  silent("local x = vim.api.nvim_buf_get_lines", "vim.api", "a bare name.ext is an identifier")

  -- ── Still reported: text prose does not write ──────────────────────────
  eq(target("see ./docs/gone.md for it", "./docs"), "./docs/gone.md", "an explicit `./` prefix")
  eq(target("see docs/gone.md for it", "docs/"), "docs/gone.md", "a component with an extension")
  eq(target("at ...nvim/init.lua now", "...nvim"), "...nvim/init.lua", "a truncation")
  eq(target("in lua/lib/nvim/nope now", "lua/lib"), "lua/lib/nvim/nope", "three or more components")

  -- The `:line[:col]` suffix is display, not path: it must not be the reason
  -- a real path fails the test, and it must not survive into the target.
  eq(
    target("boom at docs/gone.md:42 ok", "docs/gone"),
    "docs/gone.md",
    "a `:line` suffix is split off"
  )

  -- ── And a target that exists is untouched by any of it ─────────────────
  eq(target("see ./docs/real.md ok", "./docs"), "./docs/real.md", "a resolved path still hovers")

  api.nvim_win_set_buf(win, prev_buf)
  api.nvim_buf_delete(buf, { force = true })
  vim.o.isfname = prev_isfname
  vim.fn.delete(root, "rf")
end
