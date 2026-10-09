-- TESTS/autocmd_spec.lua — lib.nvim.bindings.autocmd

return function(H)
  local eq, ok = H.eq, H.ok

  local autocmd = require("lib.nvim.bindings.autocmd")

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
  local autocmd_id = autocmd.create("User", function(args)
    fired_for[#fired_for + 1] = args.buf
  end, { buffer = buf_a, desc = "spec: buffer-local autocmd" })
  eq(type(autocmd_id), "number", "create() returns the created autocmd's id")
  ok(
    vim.api.nvim_get_autocmds({ id = autocmd_id })[1] ~= nil,
    "the returned id resolves to a real autocmd"
  )

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

  -- BUG regression: get_augroup(name, { clear = true }) used to only clear on
  -- the FIRST call that created the cache entry -- every later call with
  -- clear = true silently returned the cached id without re-clearing, unlike
  -- group()'s identical contract (tested above under "Re-requesting with
  -- clear=true still clears"). A plugin rebuilding its autocommands through
  -- get_augroup on a second setup() ended up with the old ones still
  -- registered alongside the new ones instead of replaced.
  do
    local name = "lib_nvim_spec_get_augroup_clear_" .. tostring(vim.uv.hrtime())
    local id = autocmd.get_augroup(name, { clear = true })
    autocmd.create("User", function() end, { group = id, pattern = "LibNvimSpecGA" })
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

  -- ── augroup cache invalidation ────────────────────────────────────────
  -- `group()` memoizes by name. Deleting the group behind its back --
  -- `nvim_del_augroup_by_name`, which is the only way for a plugin to stop
  -- owning its autocommands -- used to leave a dead id in that cache, so the
  -- next create() against the same name failed with "Invalid 'group'".
  do
    local name = "lib_nvim_spec_group_" .. tostring(vim.uv.hrtime())

    local first = autocmd.group(name, true)
    H.ok(type(first) == "number", "group() returns an id")

    vim.api.nvim_del_augroup_by_name(name)

    local second = autocmd.group(name, true)
    H.ok(second ~= nil, "group() recreates a group that was deleted behind it")

    -- Not named `ok`: the harness's own `ok` is destructured at the top of
    -- this file, and shadowing it here would hide it for the rest of the block.
    local created = pcall(autocmd.create, "User", function() end, {
      group = second,
      pattern = "LibNvimSpec",
    })
    H.ok(created, "the recreated id is usable")

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- Re-requesting with clear=true still clears, so a rebuild does not double
  -- its autocommands.
  do
    local name = "lib_nvim_spec_clear_" .. tostring(vim.uv.hrtime())
    local id = autocmd.group(name, true)
    autocmd.create("User", function() end, { group = id, pattern = "LibNvimSpecA" })
    H.eq(#vim.api.nvim_get_autocmds({ group = id }), 1, "one autocmd registered")

    local again = autocmd.group(name, true)
    H.eq(#vim.api.nvim_get_autocmds({ group = again }), 0, "clear=true emptied the group")

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- `raw = true` hands the callback to Neovim unwrapped, so the two things
  -- the pcall wrapper eats keep working: a `true` return deletes the autocmd,
  -- and an `error()` reaches Neovim -- which is what a BufWritePre guard needs
  -- in order to cancel the write. Both used to force such callers off this
  -- module entirely, which cost them their record and their row in the
  -- generated table. Asserted on the self-delete, because that one is
  -- observable without depending on how a given setup surfaces errors.
  do
    local name = "lib_nvim_spec_raw_" .. tostring(vim.uv.hrtime())
    local id = autocmd.group(name, true)

    autocmd.create("User", function()
      return true
    end, { group = id, pattern = "LibNvimSpecWrapped" })

    autocmd.create("User", function()
      return true
    end, { group = id, pattern = "LibNvimSpecRaw", raw = true })

    H.eq(#autocmd.registered({ group = name }), 2, "both are recorded")

    vim.api.nvim_exec_autocmds("User", { pattern = "LibNvimSpecWrapped" })
    vim.api.nvim_exec_autocmds("User", { pattern = "LibNvimSpecRaw" })

    local left = {}
    for _, a in ipairs(vim.api.nvim_get_autocmds({ group = id })) do
      left[#left + 1] = a.pattern
    end
    H.eq(#left, 1, "one of the two deleted itself")
    H.eq(left[1], "LibNvimSpecWrapped", "the wrapped one survived; the raw one honored its `true`")

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- `delete(id)` drops the autocmd AND its record. `nvim_del_autocmd` alone
  -- leaves the record, so the generated table goes on listing something that
  -- no longer fires -- the precise failure this registry exists to prevent.
  do
    local name = "lib_nvim_spec_delete_" .. tostring(vim.uv.hrtime())
    local id = autocmd.group(name, true)

    local a = autocmd.create("User", function() end, { group = id, pattern = "SpecDelA" })
    autocmd.create("User", function() end, { group = id, pattern = "SpecDelB" })
    H.eq(#autocmd.registered({ group = name }), 2, "two autocmds recorded")

    H.eq(autocmd.delete(a), true, "delete() reports success for a live id")
    H.eq(#autocmd.registered({ group = name }), 1, "delete() forgets the record too")
    H.eq(#vim.api.nvim_get_autocmds({ group = id }), 1, "delete() removed the autocmd itself")
    H.eq(
      autocmd.registered({ group = name })[1].pattern,
      "SpecDelB",
      "the surviving record is the other one"
    )

    -- nvim tolerates deleting an id it already dropped, and refuses one it
    -- never issued. `delete` reports that verdict rather than raising either
    -- way, so a teardown can be as unconditional as it wants to be.
    H.eq(autocmd.delete(a), true, "deleting an already-deleted id is tolerated")
    H.eq(autocmd.delete(2 ^ 30), false, "deleting an id nvim never issued reports false")

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- `record = false`: the autocmd exists and fires, it just is not recorded.
  -- A popup's per-window hooks are created under a group named after the window
  -- id -- new every time, never asked for again -- so their records would
  -- outlive them for good; the kit passes this for those. The default stays
  -- "recorded", and a `once` autocmd keeps its record after it fired.
  do
    local name = "lib_nvim_spec_record_" .. tostring(vim.uv.hrtime())
    local id = autocmd.group(name, true)
    local fired = 0

    autocmd.create("User", function()
      fired = fired + 1
    end, { group = id, pattern = "SpecRecOff", record = false })
    autocmd.create("User", function() end, { group = id, pattern = "SpecRecDefault" })
    autocmd.create("User", function() end, { group = id, pattern = "SpecRecOnce", once = true })

    local recs = autocmd.registered({ group = name })
    local patterns = {}
    for _, r in ipairs(recs) do
      patterns[#patterns + 1] = r.pattern
    end
    table.sort(patterns)
    H.eq(table.concat(patterns, ","), "SpecRecDefault,SpecRecOnce", "record = false is left out")
    H.eq(#vim.api.nvim_get_autocmds({ group = id }), 3, "...but all three are real autocmds")

    vim.api.nvim_exec_autocmds("User", { pattern = "SpecRecOff" })
    H.eq(fired, 1, "an unrecorded autocmd still fires")

    vim.api.nvim_exec_autocmds("User", { pattern = "SpecRecOnce" })
    H.eq(#autocmd.registered({ group = name }), 2, "a fired `once` autocmd keeps its record")

    vim.api.nvim_del_augroup_by_name(name)
  end

  -- ------------------------------------------------------------ M.augroup
  local direct = autocmd.augroup.create.clear("spec.autocmd.direct")
  eq(type(direct), "number", "augroup.create.clear(): returns an augroup id")
  vim.api.nvim_del_augroup_by_id(direct)
  -- ------------------------------------------- clearing forgets the records
  -- Regression: get_augroup(name, { clear = true }) and augroup.create.clear
  -- cleared natively but kept the records, so every setup() grew the registry
  -- with ghosts of autocmds that no longer fire (K2 in cascade, spotlight ...).
  do
    local name = "lib_nvim_spec_forget_" .. tostring(vim.uv.hrtime())
    for _ = 1, 3 do
      local id = autocmd.get_augroup(name, { clear = true })
      autocmd.create("User", function() end, { group = id, pattern = "LibNvimSpecForget" })
    end
    eq(
      #autocmd.registered({ group = name }),
      1,
      "get_augroup(clear): one record after three setups"
    )
    eq(#vim.api.nvim_get_autocmds({ group = name }), 1, "get_augroup(clear): one live autocmd")

    -- An id handed to create() is attributed to the group name.
    local id = autocmd.get_augroup(name)
    autocmd.create("User", function() end, { group = id, pattern = "LibNvimSpecForget2" })
    eq(#autocmd.registered({ group = name }), 2, "a record made through the id names the group")

    autocmd.augroup.create.clear(name)
    eq(
      #autocmd.registered({ group = name }),
      0,
      "augroup.create.clear forgets the records of the group"
    )
    vim.api.nvim_del_augroup_by_name(name)

    -- A prefixed group is cleared and forgotten under its full name.
    local pname = "lib_nvim_spec_forget_p_" .. tostring(vim.uv.hrtime())
    for _ = 1, 2 do
      local pid = autocmd.get_augroup("g", { clear = true, prefix = pname })
      autocmd.create("User", function() end, { group = pid, pattern = "LibNvimSpecForget3" })
    end
    eq(
      #autocmd.registered({ group = pname .. ".g" }),
      1,
      "prefixed group: one record after two setups"
    )
    vim.api.nvim_del_augroup_by_name(pname .. ".g")
  end

  -- Groups deleted behind the module's back (a popup's per-window group) must
  -- not stay in the id caches for good.
  do
    -- one popup after the other: its group is created, then deleted when it closes. The
    -- threshold is process state (other specs raise it), so look for the prune itself --
    -- the cache shrinking -- not for a fixed size; it must come within twice the current
    -- size.
    local live = autocmd.group("LibNvimSpecChurnLive")
    local peak, pruned = autocmd._cache_size(), false
    for i = 1, 2 * peak + 100 do
      vim.api.nvim_del_augroup_by_id(autocmd.group("LibNvimSpecChurn" .. i))
      local size = autocmd._cache_size()
      if size < peak then
        pruned = true
        break
      end
      peak = size
    end
    ok(pruned, "dead groups are pruned from the caches once they have outgrown the threshold")
    -- a live group is still known by name after the prune (the id alone proves nothing: Neovim
    -- hands out the same id for an existing name): a record made through its id names it
    autocmd.create("User", function() end, { group = live, pattern = "LibNvimSpecChurnLive" })
    local named = #autocmd.registered({ group = "LibNvimSpecChurnLive" })
    -- clean up before asserting (a failing run must not leave the group or its record behind)
    autocmd.forget_group("LibNvimSpecChurnLive")
    vim.api.nvim_del_augroup_by_id(live)
    eq(named, 1, "a live group keeps its name in the cache")
  end

  -- A growing set of LIVE groups must not be scanned in full for every new group: the
  -- threshold follows the live count, so the probes grow linearly (about 2 per group;
  -- 300 groups cost ~460 probes, a threshold that only ever grew cost ~43000).
  do
    local probes, real = 0, vim.api.nvim_get_autocmds
    local names = {}
    H.with_patched(vim.api, "nvim_get_autocmds", function(...)
      probes = probes + 1
      return real(...)
    end, function()
      for i = 1, 300 do
        names[i] = "LibNvimSpecLive" .. i
        autocmd.group(names[i])
      end
    end)
    for _, name in ipairs(names) do
      pcall(vim.api.nvim_del_augroup_by_name, name)
    end
    ok(probes < 3000, ("300 live groups cost %d prune probes"):format(probes))
  end
end
