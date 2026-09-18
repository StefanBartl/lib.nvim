-- TESTS/nvim_autocmd_spec.lua — lib.nvim.autocmd
--
-- No prior coverage existed for this module. It predates
-- `lib.nvim.bindings.autocmd` (the two are near-duplicates: same `group`/
-- `get_augroup`/`create`/`norm_events`/`norm_pattern` shape, minus the
-- newer module's record-keeping, dispatcher and docs generator) and is
-- still required directly -- not through a deprecation shim -- by
-- `lib.nvim.telemetry` and documented as public API in its own README, so
-- it is reachable by any plugin using `require("lib.nvim.autocmd")` even
-- though `lib.nvim.bindings.init.lua`'s header claims the pre-bindings
-- paths are "gone" (they are not; see the comment left there).
--
-- BUG: both `M.group(name, true)` and `M.get_augroup(name, {clear=true})`
-- only actually cleared the augroup on the call that FIRST created the
-- cache entry -- a later call with the same name and `clear = true` hit the
-- cache and returned the id without re-clearing, silently ignoring the
-- caller's request. `lib.nvim.telemetry`'s own source carries a comment
-- naming this exact failure ("that caches by name and would stop
-- re-clearing for a second instance with the same namespace") as the reason
-- it bypasses `autocmd.group()` and calls `nvim_create_augroup` directly --
-- proof the bug was known and worked around locally rather than fixed at
-- the source. `lib.nvim.bindings.autocmd.group()` already got the real fix
-- (see its own spec); this module's `group()` and `get_augroup()`, and the
-- bindings module's `get_augroup()` too, did not.

return function(H)
  local eq, ok = H.eq, H.ok

  local autocmd = require("lib.nvim.autocmd")

  -- ------------------------------------------------------------- M.create
  local buf_a = vim.api.nvim_create_buf(false, true)
  local buf_b = vim.api.nvim_create_buf(false, true)

  local fired_for = {}
  local autocmd_id = autocmd.create("User", function(args)
    fired_for[#fired_for + 1] = args.buf
  end, { buffer = buf_a, desc = "spec: buffer-local autocmd" })
  eq(type(autocmd_id), "number", "create() returns the created autocmd's id")

  vim.api.nvim_exec_autocmds("User", { buffer = buf_a })
  eq(#fired_for, 1, "buffer-local autocmd fires for its own buffer")
  vim.api.nvim_exec_autocmds("User", { buffer = buf_b })
  eq(#fired_for, 1, "buffer-local autocmd does NOT fire for a different buffer")

  vim.api.nvim_buf_delete(buf_a, { force = true })
  vim.api.nvim_buf_delete(buf_b, { force = true })

  -- A callback error is caught and reported, not propagated (defensive wrap).
  local grp_err = vim.api.nvim_create_augroup("spec.nvim_autocmd.error", { clear = true })
  local ok_create = pcall(autocmd.create, "User", function()
    error("boom")
  end, { group = grp_err, pattern = "SpecNvimAutocmdErrorEvent" })
  eq(ok_create, true, "create() itself does not raise")
  local ok_exec =
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "SpecNvimAutocmdErrorEvent" })
  ok(ok_exec, "a callback error is swallowed (reported via notify), not propagated to the caller")
  vim.api.nvim_del_augroup_by_id(grp_err)

  -- ------------------------------------------------------------ M.group
  local g1 = autocmd.group("spec.nvim_autocmd.group_name")
  local g2 = autocmd.group("spec.nvim_autocmd.group_name")
  eq(g1, g2, "group(): the same name returns the same augroup id")

  -- BUG regression: re-requesting with clear=true must still clear, not
  -- just on the call that created the group.
  do
    local name = "lib_nvim_autocmd_spec_clear_" .. tostring(vim.uv.hrtime())
    local id = autocmd.group(name, true)
    autocmd.create("User", function() end, { group = id, pattern = "LibNvimAutocmdSpecA" })
    eq(#vim.api.nvim_get_autocmds({ group = id }), 1, "one autocmd registered")

    local again = autocmd.group(name, true)
    eq(id, again, "group(): same name still returns the same augroup id")
    eq(
      #vim.api.nvim_get_autocmds({ group = again }),
      0,
      "group(): BUG regression -- clear=true emptied the group on a second call too"
    )

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- --------------------------------------------------------- M.get_augroup
  local ga1 = autocmd.get_augroup("shared", { prefix = "spec.nvim_autocmd" })
  local ga2 = autocmd.get_augroup("shared", { prefix = "spec.nvim_autocmd" })
  eq(ga1, ga2, "get_augroup(): same name+prefix returns the same augroup id")

  local ga_other_prefix = autocmd.get_augroup("shared", { prefix = "spec.nvim_autocmd.other" })
  ok(ga_other_prefix ~= ga1, "get_augroup(): a different prefix is a different augroup")

  -- Same BUG regression, through get_augroup's opts.clear instead of
  -- group()'s positional boolean.
  do
    local name = "lib_nvim_autocmd_spec_ga_clear_" .. tostring(vim.uv.hrtime())
    local id = autocmd.get_augroup(name, { clear = true })
    autocmd.create("User", function() end, { group = id, pattern = "LibNvimAutocmdSpecGA" })
    eq(#vim.api.nvim_get_autocmds({ group = id }), 1, "one autocmd registered")

    local again = autocmd.get_augroup(name, { clear = true })
    eq(id, again, "get_augroup(): same name still returns the same augroup id")
    eq(
      #vim.api.nvim_get_autocmds({ group = again }),
      0,
      "get_augroup(): BUG regression -- clear=true emptied the group on a second call too"
    )

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- ------------------------------------------------------------ norm_events
  local explicit_events = { "BufEnter" }
  local fallback_events = { "FallbackEvent" }
  eq(
    autocmd.norm_events(explicit_events, fallback_events),
    explicit_events,
    "norm_events: keeps a non-empty explicit list"
  )
  eq(autocmd.norm_events(nil, fallback_events), fallback_events, "norm_events: nil falls back")
  eq(
    autocmd.norm_events({}, fallback_events),
    fallback_events,
    "norm_events: empty table falls back"
  )

  -- ----------------------------------------------------------- norm_pattern
  eq(autocmd.norm_pattern(nil), "*", "norm_pattern: nil becomes '*'")
  eq(autocmd.norm_pattern("*.md"), "*.md", "norm_pattern: an explicit pattern passes through")

  -- ------------------------------------------------------------ M.augroup
  local direct = autocmd.augroup.create.clear("spec.nvim_autocmd.direct")
  eq(type(direct), "number", "augroup.create.clear(): returns an augroup id")
  vim.api.nvim_del_augroup_by_id(direct)
end
