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
  }) do
    pcall(vim.keymap.del, "n", lhs)
  end
end
