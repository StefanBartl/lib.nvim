-- TESTS/config_new_spec.lua -- lib.lua.config.new (the config object of a plugin)
--
-- The point of the object: every change recomputes from DEFAULTS, so an option
-- left out of the next setup() is gone, and nothing a plugin writes into its
-- live config can reach DEFAULTS.

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("lib.lua.config")

  local function defaults()
    return {
      width = 80,
      title = "t",
      border = false,
      keymaps = { open = "o", close = "q" },
      ui = { sizes = { w = 1, h = 2 }, accent = "red" },
      groups = { "a", "b" },
      tabs = { groups = { web = { "html" }, lua = { "lua" } } },
      cb = function() end,
    }
  end

  local function same(a, b)
    if type(a) == "function" and type(b) == "function" then
      return true -- defaults() builds a new function every call
    end
    if type(a) ~= "table" or type(b) ~= "table" then
      return a == b
    end
    for k, v in pairs(a) do
      if not same(v, b[k]) then
        return false
      end
    end
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    return true
  end

  local function has(issues, needle)
    for _, line in ipairs(issues) do
      if line:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  -- ----------------------------------------------------- fresh from the defaults
  local D = defaults()
  local cfg = config.new(D, { name = "demo", schema = { border = "string|false" } })
  ok(same(cfg.get(), defaults()), "new: get() before any setup() is the defaults")
  cfg.setup(nil)
  ok(same(cfg.get(), defaults()), "setup(nil): exactly the defaults")

  cfg.setup({ width = 100, ui = { accent = "blue" } })
  eq(cfg.get("width"), 100, "setup: an option is applied")
  eq(cfg.get("ui.accent"), "blue", "setup: a nested option is applied")
  eq(cfg.get("ui.sizes.w"), 1, "setup: its sibling keeps the default")
  cfg.setup({ title = "other" })
  eq(cfg.get("width"), 80, "re-setup without an option: the default is back")
  eq(cfg.get("ui.accent"), "red", "re-setup without a nested option: the default is back")
  eq(cfg.get("title"), "other", "re-setup: the new option applies")
  cfg.setup({})
  ok(same(cfg.get(), defaults()), "setup({}): the defaults again")
  cfg.setup({ width = 5 })
  cfg.reset()
  eq(cfg.get("width"), 80, "reset(): the defaults again")

  -- ------------------------------------------------------------------ no sharing
  cfg.setup({ width = 100 })
  cfg.get().keymaps.open = "x"
  cfg.get().ui.sizes.w = 99
  ok(same(D, defaults()), "writing into the live config leaves DEFAULTS alone")
  cfg.setup({ width = 100 })
  eq(cfg.get("keymaps.open"), "o", "...and the next setup() starts from the real defaults")
  local snap = cfg.snapshot()
  snap.ui.sizes.w = 7
  eq(cfg.get("ui.sizes.w"), 1, "snapshot(): a copy, writing to it changes nothing")

  local opts = { keymaps = { open = "z" }, groups = { "q" } }
  cfg.setup(opts)
  cfg.get().keymaps.open = "changed"
  cfg.get().groups[1] = "changed"
  eq(opts.keymaps.open, "z", "the caller's opts are not shared with the config")
  eq(opts.groups[1], "q", "...lists included")
  eq(cfg.get("groups")[1], "changed", "(the config itself is writable outside the checking mode)")

  -- ------------------------------------------------------------ check and report
  local told = {}
  local checked = config.new(defaults(), {
    name = "demo",
    schema = { border = "string|false", ["ui.accent"] = { "string", enum = { "red", "blue" } } },
    optional = { telemetry = "table" },
    notify = function(msg)
      told[#told + 1] = msg
    end,
  })
  checked.setup({
    widht = 5,
    width = "wide",
    ui = { accent = "green", sizes = { w = "x" } },
    border = "rounded",
  })
  eq(checked.get("width"), 80, "a wrong type falls back to the default")
  eq(checked.get("widht"), nil, "an unknown key is not stored")
  eq(checked.get("ui.accent"), "red", "an enum miss falls back to the default")
  eq(checked.get("ui.sizes.w"), 1, "a nested wrong type falls back to the default")
  eq(checked.get("border"), "rounded", "an exception widens a false default")
  local list = checked.issues()
  eq(#list, 4, "four problems: " .. table.concat(list, " | "))
  ok(has(list, "unknown option 'widht' (did you mean 'width'?)"), "the typo has a hint")
  ok(has(list, "option 'ui.sizes.w' must be a number"), "the nested path is named")
  eq(#told, 1, "notify is called once for the layer")
  ok(
    told[1]:find("ignored config:", 1, true) == 1 and told[1]:find("widht", 1, true) ~= nil,
    "notify carries the problems: " .. told[1]
  )
  checked.setup({ telemetry = {} })
  eq(#checked.issues(), 0, "an optional key without a default is accepted")
  eq(#told, 1, "a clean layer notifies nothing")
  checked.setup("nonsense")
  ok(
    has(checked.issues(), 'setup() takes a table of options, got "nonsense"'),
    "a non-table setup() argument is reported"
  )
  ok(same(checked.get(), defaults()), "...and ignored")

  -- --------------------------------------------------------------- merge rules
  local m = config.new(defaults(), {
    schema = { ["tabs.groups"] = { "table", of = { "table|false", of = "string" } } },
    merge = { ["tabs.groups"] = "entries", groups = "replace" },
  })
  m.setup({ tabs = { groups = { web = { "html", "css" }, go = { "go" } } } })
  eq(#m.get("tabs.groups.web"), 2, "entries: a named entry is replaced as a whole")
  eq(m.get("tabs.groups.lua")[1], "lua", "entries: an entry the user does not name stays")
  eq(m.get("tabs.groups.go")[1], "go", "entries: a new entry is added")
  m.setup({ tabs = { groups = { lua = false } } })
  eq(m.get("tabs.groups.lua"), nil, "entries: false removes the default entry")
  eq(m.get("tabs.groups.web")[1], "html", "entries: ...the others stay")
  m.setup({ groups = {} })
  eq(#m.get("groups"), 0, "replace: {} is an empty set")
  local r = config.new(defaults(), { merge = { keymaps = "replace" } })
  r.setup({ keymaps = { open = "x" } })
  eq(r.get("keymaps.close"), nil, "replace: a map replaces instead of merging")
  local e = config.new(defaults())
  e.setup({ keymaps = {} })
  eq(e.get("keymaps.open"), "o", "{} over a map changes nothing")
  eq(e.get("keymaps.close"), "q", "...no key of it is lost")
  local bad_ok = pcall(config.new, defaults(), { merge = { x = "sideways" } })
  ok(not bad_ok, "an unknown merge rule is an error")

  -- ------------------------------------------------------------ normalize/resolve
  local seen_prev = {}
  local hooks = config.new(defaults(), {
    schema = { keymaps = "table" },
    normalize = function(o)
      if o.keymaps == false then
        o.keymaps = { open = "<nop>", close = "<nop>" }
      end
    end,
    resolve = function(c, issues)
      if c.width > 200 then
        issues[#issues + 1] = "width above 200 -- using 200"
        c.width = 200
      end
      c.area = c.width * 2
    end,
    on_change = function(c, prev)
      seen_prev[#seen_prev + 1] = { now = c.width, before = prev and prev.width }
    end,
  })
  local given = { keymaps = false, width = 300 }
  hooks.setup(given)
  eq(given.keymaps, false, "normalize works on a copy, the caller's opts keep their spelling")
  eq(hooks.get("keymaps.open"), "<nop>", "normalize: liberal in, canonical out")
  eq(hooks.get("width"), 200, "resolve may degrade a value")
  eq(hooks.get("area"), 400, "resolve may derive a value")
  ok(has(hooks.issues(), "width above 200"), "resolve's problems are in issues()")
  hooks.setup({ width = 10 })
  eq(hooks.get("area"), 20, "resolve runs on every change")
  eq(#hooks.issues(), 0, "...and its old problems are gone")
  ok(#seen_prev >= 2, "on_change runs on every change")
  eq(seen_prev[#seen_prev].before, 200, "on_change gets the previous config")
  eq(seen_prev[#seen_prev].now, 10, "...and the new one")

  -- ----------------------------------------------------------------- layers
  local told_layers = {}
  local L = config.new(defaults(), {
    name = "lsp",
    layers = { "preset", "setup", "project" },
    notify = function(msg)
      told_layers[#told_layers + 1] = msg
    end,
  })
  L.layer("preset", { width = 10, title = "preset" })
  L.setup({ width = 20 })
  L.layer("project", { width = 30 })
  eq(L.get("width"), 30, "layers: the highest layer wins")
  eq(L.get("title"), "preset", "layers: a lower layer shows where a higher one is silent")
  eq(L.source("width"), "project", "source: the layer a value comes from")
  eq(L.source("title"), "preset", "source: ...a lower one")
  eq(L.source("ui.accent"), "default", "source: the default")
  eq(L.source("nothing.here"), nil, "source: unknown path")
  L.layer("project", nil)
  eq(L.get("width"), 20, "layers: removing a layer lets the next one show")
  L.setup({ title = "mine" })
  eq(L.get("width"), 10, "layers: a re-setup drops only its own options, the preset's stay")
  eq(L.get("title"), "mine", "layers: ...and the new ones apply")
  L.layer("project", { widht = 1 })
  ok(
    has(L.issues(), "project layer: unknown option 'widht'"),
    "layers: a problem names its layer: " .. table.concat(L.issues(), " | ")
  )
  eq(#told_layers, 1, "layers: only the layer that was set notifies")
  L.setup({ title = "again" })
  eq(#told_layers, 1, "layers: setting another layer does not repeat the old problem")
  ok(not pcall(L.layer, "bogus", {}), "layers: an unknown layer name is an error")
  ok(
    not pcall(config.new, defaults(), { layers = { "preset" } }),
    "layers: the list must contain setup"
  )

  -- ----------------------------------------------------------------- stable
  local S = config.new(defaults(), { stable = true })
  local ui = S.get("ui")
  local root = S.get()
  S.setup({ ui = { accent = "blue" }, extra = 1 })
  eq(S.get(), root, "stable: the same table after setup()")
  eq(S.get("ui"), ui, "stable: ...and the same sub-table")
  eq(ui.accent, "blue", "stable: the held sub-table holds the new value")
  eq(S.get("extra"), nil, "stable: the unknown key is dropped")
  S.setup({ ui = { sizes = { w = 9 } } })
  eq(ui.sizes.w, 9, "stable: a held reference sees the new value")
  eq(ui.accent, "red", "stable: an option left out is back to its default in place")
  local N = config.new(defaults())
  local before = N.get()
  N.setup({ width = 1 })
  ok(N.get() ~= before, "not stable: a new table after setup()")

  -- --------------------------------------------------------- checking mode
  eq(config.is_checked(), false, "the checking mode is off by default")
  config.set_checked(true)
  local C = config.new(defaults(), { name = "guarded" })
  C.get().width = 1
  local fine, err = pcall(C.get)
  ok(
    not fine
      and tostring(err):find("guarded: the config table was written to at 'width'", 1, true)
        ~= nil,
    "checked: a write is caught at the next get(): " .. tostring(err)
  )
  C.setup({ width = 2 })
  local snap2 = C.snapshot()
  snap2.width = 5
  eq(C.get("width"), 2, "checked: writing to a snapshot is fine")
  config.set_checked(false)
  C.get().width = 7
  eq(C.get("width"), 7, "unchecked: nothing is verified")
end
