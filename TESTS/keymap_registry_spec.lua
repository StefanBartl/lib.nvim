-- TESTS/keymap_registry_spec.lua — lib.nvim.bindings.keymap

return function(H)
  local eq, ok = H.eq, H.ok

  local keymap = require("lib.nvim.bindings.keymap")

  ---@param lhs string
  ---@param mode string|nil
  ---@return boolean
  local function mapped(lhs, mode)
    return vim.fn.maparg(lhs, mode or "n") ~= ""
  end

  -- ------------------------------------------------------- callable module
  --
  -- The module used to *be* the set-function (`lib.nvim.map`), and it is
  -- required that way in over a hundred places across these plugins. Adding
  -- the registry must not turn it into a plain table.

  keymap("n", "<Plug>(libspec-callable)", function() end, {}, "callable form")
  ok(mapped("<Plug>(libspec-callable)"), "calling the module directly still sets a keymap")

  keymap.set("n", "<Plug>(libspec-set)", function() end, {}, "set form")
  ok(mapped("<Plug>(libspec-set)"), "keymap.set() sets a keymap")

  -- ------------------------------------------------------------- register
  --
  -- The override table is keyed by ACTION NAME, not by the current lhs, so
  -- that "disable this one" and "the default moved" are both expressible.

  ---@type Lib.Keymap.Spec
  local spec = {
    prefix = "<Plug>(libspec-",
    order = { "alpha", "beta", "gamma", "keyless" },
    actions = {
      alpha = {
        default = "<Plug>(libspec-alpha)",
        rhs = function() end,
        desc = "alpha",
      },
      beta = { default = "<Plug>(libspec-beta)", rhs = function() end, desc = "beta" },
      gamma = { default = "<Plug>(libspec-gamma)", rhs = function() end, desc = "gamma" },
      -- Declared with no default: reachable through the API/commands only.
      -- Not an error, and must still be recorded.
      keyless = { rhs = function() end, desc = "keyless" },
    },
  }

  local bound = keymap.register("libspec", spec, {
    beta = "<Plug>(libspec-beta-moved)",
    gamma = false,
  })

  ok(mapped("<Plug>(libspec-alpha)"), "an untouched action binds its default")
  ok(mapped("<Plug>(libspec-beta-moved)"), "a remapped action binds the user's lhs")
  ok(not mapped("<Plug>(libspec-beta)"), "a remapped action leaves its default free")
  ok(not mapped("<Plug>(libspec-gamma)"), "`false` drops exactly that one mapping")

  eq(#bound, 4, "every declared action is recorded, bound or not")
  eq(bound[1].name, "alpha", "spec.order fixes the recorded order (1)")
  eq(bound[4].name, "keyless", "spec.order fixes the recorded order (4)")
  eq(bound[3].bound, false, "a disabled action is recorded as not bound")
  eq(bound[4].lhs, nil, "an action without a default has no lhs")
  eq(bound[4].bound, false, "an action without a default is not bound")

  -- desc reaches the real mapping, prefixed with the plugin name, because
  -- that is what which-key and `:map` display.
  local m = vim.fn.maparg("<Plug>(libspec-alpha)", "n", false, true)
  eq(m.desc, "libspec: alpha", "desc is prefixed with the plugin name")

  -- ------------------------------------------------------ preset = false
  --
  -- Binds nothing, but still records: the health check and the generated
  -- docs want to know what EXISTS, not only what is bound right now.

  local off = keymap.register("libspec_off", {
    order = { "solo" },
    actions = { solo = { default = "<Plug>(libspec-off)", rhs = function() end, desc = "solo" } },
  }, { preset = false })

  ok(not mapped("<Plug>(libspec-off)"), "preset = false binds nothing")
  eq(#off, 1, "preset = false still records the action")
  eq(off[1].bound, false, "preset = false records it as not bound")

  -- ------------------------------------------------------- introspection

  eq(#keymap.registered("libspec"), 4, "registered(plugin) returns that plugin's actions")
  ok(keymap.registered()["libspec"] ~= nil, "registered() returns every plugin")

  -- --------------------------------------------------------- conflicts()
  --
  -- Not checked during registration: a plugin cannot know what a later one
  -- will bind, so the answer only means anything once everything has loaded.

  keymap.register("libspec_clash", {
    order = { "clash" },
    actions = {
      clash = { default = "<Plug>(libspec-alpha)", rhs = function() end, desc = "clash" },
    },
  }, nil)

  local found = false
  for _, c in ipairs(keymap.conflicts()) do
    if c.lhs == "<Plug>(libspec-alpha)" then
      found = true
      eq(#c.claimants, 2, "both claimants of the contested lhs are reported")
    end
  end
  ok(found, "conflicts() reports an lhs claimed by two plugins")

  -- --------------------------------------------- override with options
  --
  -- Some plugins let a mapping carry options beside its key (insights: the
  -- scope and symbol type a mapping opens with). Such an override is a table
  -- WITH an `lhs` field; a plain list of keys is a table WITHOUT one. The two
  -- cannot be confused, and both have to keep working -- migrating a plugin
  -- must not silently break its users' existing config.

  local opts_over = keymap.register("libspec_lhsfield", {
    order = { "a", "b" },
    actions = {
      a = { default = "<Plug>(libspec-lf1)", rhs = function() end, desc = "a" },
      b = { default = "<Plug>(libspec-lf2)", rhs = function() end, desc = "b" },
    },
  }, {
    a = { lhs = "<Plug>(libspec-lf-moved)", scope = "buffer" },
    b = { lhs = { "<Plug>(libspec-lf3)", "<Plug>(libspec-lf4)" } },
  })

  ok(mapped("<Plug>(libspec-lf-moved)"), "a table override with `lhs` binds that key")
  ok(not mapped("<Plug>(libspec-lf1)"), "and leaves the default free")
  ok(mapped("<Plug>(libspec-lf3)") and mapped("<Plug>(libspec-lf4)"), "`lhs` may itself be a list")
  eq(#opts_over, 3, "one entry per resolved key")

  -- ------------------------------------------------------- user = false
  --
  -- `mappings = false` for the whole table says the same thing as
  -- `{ preset = false }`, and several plugins here spell it the short way.
  -- Accepting both means migrating a plugin never silently changes what its
  -- users' existing config means.

  local off_all = keymap.register("libspec_falsetable", {
    order = { "a" },
    actions = { a = { default = "<Plug>(libspec-falsetable)", rhs = function() end, desc = "a" } },
  }, false)
  ok(not mapped("<Plug>(libspec-falsetable)"), "user = false binds nothing")
  eq(#off_all, 1, "user = false still records the action")
  eq(off_all[1].bound, false, "user = false records it as not bound")

  -- ------------------------------------------------------ several keys
  --
  -- One action on more than one key is a real case, not a convenience:
  -- gopath binds `open_here` to `gF` and to a double-click. It stays one
  -- action, so moving or dropping it is still said once.

  local multi_key = keymap.register("libspec_keys", {
    order = { "twokeys", "dropped" },
    actions = {
      twokeys = {
        default = { "<Plug>(libspec-k1)", "<Plug>(libspec-k2)" },
        rhs = function() end,
        desc = "two keys",
      },
      dropped = { default = { "<Plug>(libspec-k3)" }, rhs = function() end, desc = "dropped" },
    },
  }, { dropped = false })

  ok(mapped("<Plug>(libspec-k1)"), "the first of several defaults binds")
  ok(mapped("<Plug>(libspec-k2)"), "the second of several defaults binds")
  ok(not mapped("<Plug>(libspec-k3)"), "`false` drops a list-valued action too")
  eq(#multi_key, 3, "one entry per key, plus the dropped action's own")
  eq(multi_key[1].name, multi_key[2].name, "both keys share the action name")

  -- A user override may be a list as well, and replaces the defaults wholly.
  local over = keymap.register("libspec_keys2", {
    order = { "k" },
    actions = { k = { default = "<Plug>(libspec-k4)", rhs = function() end, desc = "k" } },
  }, { k = { "<Plug>(libspec-k5)", "<Plug>(libspec-k6)" } })
  ok(
    mapped("<Plug>(libspec-k5)") and mapped("<Plug>(libspec-k6)"),
    "a list override binds every key"
  )
  ok(not mapped("<Plug>(libspec-k4)"), "a list override replaces the default outright")
  eq(#over, 2, "a list override yields one entry per key")

  -- ------------------------------------------------------------- binds
  --
  -- One key, one name, one override -- but two modes calling different
  -- functions. Splitting that into two action names would make a user
  -- override the same key twice.

  local nmode_called, xmode_called = false, false
  local multi = keymap.register("libspec_binds", {
    order = { "both" },
    actions = {
      both = {
        default = "<Plug>(libspec-both)",
        desc = "fallback desc",
        binds = {
          {
            mode = "n",
            rhs = function()
              nmode_called = true
            end,
            desc = "normal variant",
          },
          {
            mode = "x",
            rhs = function()
              xmode_called = true
            end,
          },
        },
      },
    },
  }, nil)

  eq(#multi, 2, "one action with two binds yields two registered entries")
  eq(multi[1].name, multi[2].name, "both entries carry the same action name")
  eq(multi[1].lhs, multi[2].lhs, "both entries share the action's lhs")
  eq(multi[1].desc, "libspec_binds: normal variant", "a bind's own desc wins")
  eq(
    multi[2].desc,
    "libspec_binds: fallback desc",
    "a bind without desc falls back to the action's"
  )
  ok(mapped("<Plug>(libspec-both)", "n"), "the normal-mode bind is set")
  ok(mapped("<Plug>(libspec-both)", "x"), "the visual-mode bind is set")

  -- The two modes really do call different functions.
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Plug>(libspec-both)", true, false, true),
    "x",
    false
  )
  ok(nmode_called and not xmode_called, "normal mode runs its own rhs")

  -- A user override moves BOTH binds, because it is one action.
  local moved = keymap.register("libspec_binds2", {
    order = { "both" },
    actions = {
      both = {
        default = "<Plug>(libspec-both2)",
        desc = "d",
        binds = { { mode = "n", rhs = function() end }, { mode = "x", rhs = function() end } },
      },
    },
  }, { both = "<Plug>(libspec-both-moved)" })
  eq(moved[1].lhs, "<Plug>(libspec-both-moved)", "an override moves the first bind")
  eq(moved[2].lhs, "<Plug>(libspec-both-moved)", "an override moves the second bind too")

  -- ------------------------------------------------- buffer-local preset
  --
  -- images.nvim binds its whole preset per buffer from a FileType autocmd.
  -- The action set is the same in every buffer; only the target differs.

  local buf_a = vim.api.nvim_create_buf(false, true)
  local buf_b = vim.api.nvim_create_buf(false, true)
  local bspec = {
    order = { "hover" },
    actions = {
      hover = { default = "<Plug>(libspec-buf)", rhs = function() end, desc = "hover" },
    },
  }
  keymap.register("libspec_buf", bspec, nil, { buffer = buf_a })

  local function buf_mapped(buf, lhs)
    for _, mp in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if mp.lhs == lhs then
        return true
      end
    end
    return false
  end

  ok(buf_mapped(buf_a, "<Plug>(libspec-buf)"), "opts.buffer binds in that buffer")
  ok(not buf_mapped(buf_b, "<Plug>(libspec-buf)"), "and not in another")
  ok(not mapped("<Plug>(libspec-buf)"), "and not globally")

  -- Re-registering for a second buffer is the normal case, not an error.
  keymap.register("libspec_buf", bspec, nil, { buffer = buf_b })
  ok(buf_mapped(buf_b, "<Plug>(libspec-buf)"), "re-registering binds the next buffer too")
  eq(
    #keymap.registered("libspec_buf"),
    1,
    "the registry still records one action, not one per buffer"
  )

  vim.api.nvim_buf_delete(buf_a, { force = true })
  vim.api.nvim_buf_delete(buf_b, { force = true })

  -- ------------------------------------------ unknown names warn only once
  --
  -- A buffer-local preset re-registers on every FileType, so an un-deduped
  -- warning would fire once per file opened.

  local warnings = 0
  local orig = vim.notify
  vim.notify = function(msg, ...)
    if type(msg) == "string" and msg:find("no such keymap action", 1, true) then
      warnings = warnings + 1
    end
    return orig(msg, ...)
  end
  for _ = 1, 3 do
    keymap.register("libspec_warnonce", {
      order = { "real" },
      actions = { real = { rhs = function() end, desc = "real" } },
    }, { typo_here = "<Plug>(libspec-warn)" })
  end
  vim.notify = orig
  eq(warnings, 1, "an unknown name is reported once, not once per registration")

  -- --------------------------------------------------------- icon gate
  --
  -- Neovim cannot see the terminal's font -- strdisplaywidth() returns 1 even
  -- for U+10FFFD, a noncharacter no font contains -- so icons are declared,
  -- not detected, and default to off. Declaring one must never throw or bind
  -- differently either way.

  local had = vim.g.have_nerd_font
  for _, flag in ipairs({ false, true }) do
    vim.g.have_nerd_font = flag
    local iconed = keymap.register("libspec_icon_" .. tostring(flag), {
      order = { "i" },
      actions = {
        i = {
          default = "<Plug>(libspec-icon-" .. tostring(flag) .. ")",
          rhs = function() end,
          desc = "iconed",
          which_key = { icon = "X" },
        },
      },
    }, nil)
    ok(
      iconed[1].bound,
      "an action with an icon binds regardless of the font flag (" .. tostring(flag) .. ")"
    )
    pcall(vim.keymap.del, "n", iconed[1].lhs)
  end
  vim.g.have_nerd_font = had

  -- ------------------------------------------------- which_key = false
  --
  -- which-key reads keymaps and their desc on its own, so hiding is the one
  -- thing only the plugin can express. which-key's own convention for it is
  -- this magic description -- which means it works with which-key absent.

  keymap.register("libspec_wk", {
    order = { "hidden" },
    actions = {
      hidden = {
        default = "<Plug>(libspec-hidden)",
        rhs = function() end,
        desc = "hidden",
        which_key = false,
      },
    },
  }, nil)

  local hidden = vim.fn.maparg("<Plug>(libspec-hidden)", "n", false, true)
  eq(hidden.desc, "which_key_ignore", "which_key = false marks the mapping hidden")

  -- ----------------------------------------------------------- clean up
  for _, lhs in ipairs({
    "<Plug>(libspec-callable)",
    "<Plug>(libspec-set)",
    "<Plug>(libspec-alpha)",
    "<Plug>(libspec-beta-moved)",
    "<Plug>(libspec-hidden)",
    "<Plug>(libspec-both)",
    "<Plug>(libspec-k1)",
    "<Plug>(libspec-k2)",
    "<Plug>(libspec-k5)",
    "<Plug>(libspec-k6)",
    "<Plug>(libspec-both-moved)",
  }) do
    pcall(vim.keymap.del, "n", lhs)
  end
end
