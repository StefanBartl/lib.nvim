-- TESTS/config_spec.lua — lib.config
--
-- The one thing worth pinning: a typo'd option must be reported and dropped
-- before the merge, not stored as a dead field next to the default it was
-- meant to replace. `require("lib.config").setup({ startegy = "eager" })`
-- used to be completely silent.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("lib.config")

  local before = vim.deepcopy(config.get())

  local warnings = {}
  local real_notify = vim.notify
  vim.notify = function(msg, level)
    warnings[#warnings + 1] = { msg = msg, level = level }
  end

  -- Deliberately untyped: this is the shape a caller gets wrong.
  ---@type any
  local typo = { startegy = "eager" }
  config.setup(typo)
  eq(config.get().startegy, nil, "config.setup: a typo'd key is not stored")
  eq(config.get().strategy, before.strategy, "config.setup: and the real key keeps its value")
  eq(#warnings, 1, "config.setup: the unknown key is reported once")
  ok(
    warnings[1].msg:find("startegy", 1, true) ~= nil
      and warnings[1].msg:find("did you mean strategy", 1, true) ~= nil,
    "config.setup: the report names the key and the nearest known one: " .. warnings[1].msg
  )
  eq(warnings[1].level, vim.log.levels.WARN, "config.setup: reported as a warning")

  config.setup({ strategy = before.strategy })
  eq(#warnings, 1, "config.setup: a known key alone reports nothing")

  ---@type any
  local nonsense = { strategy = "nonsense" }
  config.setup(nonsense)
  eq(config.get().strategy, "metatable", "config.setup: an unknown strategy falls back to metatable")

  vim.notify = real_notify
  config.options = before
end
