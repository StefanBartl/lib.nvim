-- docs/TESTS/autocmd_spec.lua — lib.nvim.autocmd

return function(H)
  local eq, ok = H.eq, H.ok

  local autocmd = require("lib.nvim.autocmd")

  -- ------------------------------------------------------------- M.create
  --
  -- Regression: M.create used to always set `pattern` (defaulting to nil,
  -- which nvim_create_autocmd treats as "*") and silently ignored
  -- `opts.buffer` entirely -- a caller asking for a buffer-local autocmd
  -- got a GLOBAL one instead, firing on every matching event anywhere in
  -- the session, not just for its own buffer.

  local buf_a = vim.api.nvim_create_buf(false, true)
  local buf_b = vim.api.nvim_create_buf(false, true)

  local fired_for = {}
  autocmd.create("User", function(args)
    fired_for[#fired_for + 1] = args.buf
  end, { buffer = buf_a, desc = "spec: buffer-local autocmd" })

  vim.api.nvim_exec_autocmds("User", { buffer = buf_a })
  eq(#fired_for, 1, "buffer-local autocmd fires for its own buffer")

  vim.api.nvim_exec_autocmds("User", { buffer = buf_b })
  eq(#fired_for, 1, "buffer-local autocmd does NOT fire for a different buffer")

  vim.api.nvim_buf_delete(buf_a, { force = true })
  vim.api.nvim_buf_delete(buf_b, { force = true })

  -- A pattern-based (non-buffer) autocmd keeps working exactly as before.
  local pattern_fired = 0
  local grp = vim.api.nvim_create_augroup("spec.autocmd.pattern", { clear = true })
  autocmd.create("User", function()
    pattern_fired = pattern_fired + 1
  end, { group = grp, pattern = "SpecAutocmdPatternEvent" })

  vim.api.nvim_exec_autocmds("User", { pattern = "SpecAutocmdPatternEvent" })
  eq(pattern_fired, 1, "pattern-based autocmd still fires on a matching pattern")
  vim.api.nvim_exec_autocmds("User", { pattern = "SomeOtherEvent" })
  eq(pattern_fired, 1, "pattern-based autocmd does not fire on a non-matching pattern")

  vim.api.nvim_del_augroup_by_id(grp)

  -- A callback error is caught and reported, not propagated (defensive wrap).
  local grp2 = vim.api.nvim_create_augroup("spec.autocmd.error", { clear = true })
  local ok_create = pcall(autocmd.create, "User", function()
    error("boom")
  end, { group = grp2, pattern = "SpecAutocmdErrorEvent" })
  eq(ok_create, true, "create() itself does not raise")

  local ok_exec = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "SpecAutocmdErrorEvent" })
  ok(ok_exec, "a callback error is swallowed (reported via notify), not propagated to the caller")

  vim.api.nvim_del_augroup_by_id(grp2)

  -- ------------------------------------------------------------ M.group
  local g1 = autocmd.group("spec.autocmd.group_name")
  local g2 = autocmd.group("spec.autocmd.group_name")
  eq(g1, g2, "group(): the same name returns the same augroup id")

  -- --------------------------------------------------------- M.get_augroup
  local ga1 = autocmd.get_augroup("shared", { prefix = "spec.autocmd" })
  local ga2 = autocmd.get_augroup("shared", { prefix = "spec.autocmd" })
  eq(ga1, ga2, "get_augroup(): same name+prefix returns the same augroup id")

  local ga_other_prefix = autocmd.get_augroup("shared", { prefix = "spec.autocmd.other" })
  ok(ga_other_prefix ~= ga1, "get_augroup(): a different prefix is a different augroup")

  -- ------------------------------------------------------------ norm_events
  --
  -- `eq` compares with `~=`, which is identity (not value) equality for
  -- tables -- so the expected value here must be the SAME table reference
  -- norm_events is documented to hand back unchanged, not an equal-looking
  -- new literal.
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
end
