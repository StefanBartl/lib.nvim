-- TESTS/config_merge_spec.lua -- lib.lua.config.deep_merge / copy
--
-- What a config store needs from its merge: the result shares no table with the
-- defaults (a later write into the live config must not change what the next
-- setup() starts from), nor with the caller's opts, and an empty table
-- follows the shape of the default instead of wiping a section.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("lib.lua.config")

  local function defaults()
    return {
      keys = { open = "<CR>", close = "q" },
      ui = { border = "rounded", sizes = { w = 80, h = 20 } },
      groups = { "a", "b", "c" },
      none = {},
      cb = function() end,
    }
  end

  -- ----------------------------------------------------------- no shared tables
  local base = defaults()
  local merged = config.deep_merge(base, { ui = { border = "none" } })
  ok(merged.keys ~= base.keys, "deep_merge: an untouched branch is a copy, not the default table")
  ok(
    merged.ui.sizes ~= base.ui.sizes,
    "deep_merge: an untouched branch below a merged one is a copy too"
  )
  ok(merged.groups ~= base.groups, "deep_merge: an untouched list is a copy")
  merged.keys.open = "x"
  merged.ui.sizes.w = 1
  merged.groups[1] = "z"
  eq(
    base.keys.open,
    "<CR>",
    "deep_merge: writing into an untouched branch leaves the defaults alone"
  )
  eq(base.ui.sizes.w, 80, "deep_merge: writing two levels down leaves the defaults alone")
  eq(base.groups[1], "a", "deep_merge: writing into a copied list leaves the defaults alone")
  eq(merged.cb, base.cb, "deep_merge: a function value is kept as it is")

  local opts = { ui = { sizes = { w = 5 } }, extra = { deep = { v = 1 } }, list = { "q" } }
  local from_opts = config.deep_merge(defaults(), opts)
  ok(
    from_opts.extra ~= opts.extra and from_opts.extra.deep ~= opts.extra.deep,
    "deep_merge: a table only the caller has is copied"
  )
  ok(from_opts.list ~= opts.list, "deep_merge: a caller's list is copied")
  from_opts.extra.deep.v = 2
  from_opts.list[1] = "changed"
  eq(opts.extra.deep.v, 1, "deep_merge: writing into the result leaves the caller's opts alone")
  eq(opts.list[1], "q", "deep_merge: ...lists included")

  -- ---------------------------------------------------------------- empty {} rule
  local e1 = config.deep_merge(defaults(), { keys = {} })
  eq(e1.keys.open, "<CR>", "deep_merge: {} over a map changes nothing")
  eq(e1.keys.close, "q", "deep_merge: ...no key of the map is lost")
  local e2 = config.deep_merge(defaults(), { groups = {} })
  eq(#e2.groups, 0, "deep_merge: {} over a list means no entries")
  local e3 = config.deep_merge(defaults(), { none = { "x" } })
  eq(e3.none[1], "x", "deep_merge: a list over an empty default replaces it")
  local e4 = config.deep_merge(defaults(), { none = {} })
  eq(next(e4.none), nil, "deep_merge: {} over an empty default stays empty")
  local e5 = config.deep_merge(defaults(), { ui = {} })
  eq(e5.ui.sizes.w, 80, "deep_merge: {} over a nested map keeps its branches")

  -- ----------------------------------------------------------- list / shape rules
  local l1 = config.deep_merge(defaults(), { groups = { "x" } })
  eq(#l1.groups, 1, "deep_merge: a shorter list replaces, no tail of the default")
  local l2 = config.deep_merge(defaults(), { keys = { "x", "y" } })
  eq(#l2.keys, 2, "deep_merge: a list over a map replaces the map")
  eq(l2.keys.open, nil, "deep_merge: ...no key of the map survives")
  local l3 = config.deep_merge(defaults(), { groups = { open = "k" } })
  eq(l3.groups.open, "k", "deep_merge: a map over a list replaces the list")
  eq(#l3.groups, 0, "deep_merge: ...no element of the list survives")
  local s1 = config.deep_merge(defaults(), { ui = false })
  eq(s1.ui, false, "deep_merge: false over a table replaces it")
  local s2 = config.deep_merge(defaults(), { keys = { open = "o" } })
  eq(s2.keys.open, "o", "deep_merge: a nested key overrides")
  eq(s2.keys.close, "q", "deep_merge: ...and its sibling stays")

  -- ------------------------------------------------------------------------ copy
  local cyc = { name = "c" }
  cyc.self = cyc
  local cc = config.copy(cyc)
  ok(cc ~= cyc and cc.self == cc, "copy: a cyclic table copies once and stays cyclic")
  local shared = { v = 1 }
  local two = config.copy({ a = shared, b = shared })
  ok(two.a == two.b and two.a ~= shared, "copy: a table referenced twice is copied once")
  local mt = {
    __index = function()
      return 7
    end,
  }
  eq(
    getmetatable(config.copy(setmetatable({}, mt))),
    mt,
    "copy: the metatable is carried over by reference"
  )
  eq(config.copy(5), 5, "copy: a scalar is returned as it is")
  local keyed = config.copy({ [{ 1 }] = "t" })
  local only_key = next(keyed)
  eq(only_key[1], 1, "copy: a table used as key is copied as well")
end
