-- TESTS/keymap_runtime_spec.lua — lib.nvim.bindings.keymap.runtime (+ the :LibKeymap* commands)
---@diagnostic disable: need-check-nil

return function(H)
  local eq, ok = H.eq, H.ok

  local rt = require("lib.nvim.bindings.keymap.runtime")
  local keymap = require("lib.nvim.bindings.keymap")

  local function noop() end

  ---@param list Lib.Keymap.RuntimeEntry[]
  ---@param mode string
  ---@param key string
  ---@return Lib.Keymap.RuntimeEntry|nil
  local function find(list, mode, key)
    for _, e in ipairs(list) do
      if e.mode == mode and e.key == key and e.buffer == nil then
        return e
      end
    end
  end

  -- ------------------------------------------------------------- snapshot

  do
    local marker_line
    vim.keymap.set("n", "<M-F7>", noop, { desc = "[spec] snapshot probe" })
    marker_line = debug.getinfo(1, "l").currentline - 1
    local snap = rt.snapshot()
    local e = find(snap, "n", "<M-F7>")
    ok(e ~= nil, "snapshot lists a mapping the test just set")
    eq(e.callback, true, "a Lua callback is flagged as one")
    eq(e.desc, "[spec] snapshot probe", "with its description")
    eq(e.origin, "other", "which is neither a Neovim default nor lib.nvim's")
    ok(
      e.source ~= nil and e.source:find("keymap_runtime_spec.lua", 1, true) ~= nil,
      "and the file that set it: " .. tostring(e.source)
    )
    eq(e.lnum, marker_line, "and the line")
    ok(e.sid ~= nil and e.sid > 1, "plus its script id")

    keymap("n", "<M-F6>", noop, { record = true }, "lib probe")
    local lib = find(rt.snapshot(), "n", "<M-F6>")
    eq(lib.origin, "lib", "a mapping lib.nvim recorded is marked as such")
    keymap.forget()

    -- Neovim's own defaults: by script id where it stamps them, by content
    -- against the pristine list where it does not (a build with its Lua
    -- compiled in).
    local pristine = rt.pristine_defaults()
    if not pristine then
      H.skipped("builtin origin", "no pristine defaults to compare with")
    else
      local builtin = 0
      for _, m in ipairs(rt.snapshot({ defaults = pristine })) do
        if m.origin == "builtin" then
          builtin = builtin + 1
        end
      end
      ok(builtin > 0, "Neovim's own default mappings are recognised (" .. builtin .. ")")
    end

    -- The content fallback itself: a mapping from a script that is not a real
    -- file, identical to a default, is that default; one from a real file is
    -- not, whatever it says.
    load(
      "vim.keymap.set('n', '<M-F1>', ':echo fallback<CR>', { desc = 'fallback probe' })",
      "@vim/fake_defaults.lua"
    )()
    local fake_default = {
      mode = "n",
      lhs = "<M-F1>",
      key = "<M-F1>",
      rhs = ":echo fallback<CR>",
      desc = "fallback probe",
    }
    eq(
      find(rt.snapshot({ defaults = {} }), "n", "<M-F1>").origin,
      "other",
      "without a matching default it is not builtin"
    )
    eq(
      find(rt.snapshot({ defaults = { fake_default } }), "n", "<M-F1>").origin,
      "builtin",
      "with one, a mapping from no real file is"
    )
    vim.keymap.set("n", "<M-F4>", ":echo fallback<CR>", { desc = "fallback probe" })
    local real = find(
      rt.snapshot({
        defaults = { vim.tbl_extend("force", fake_default, { lhs = "<M-F4>", key = "<M-F4>" }) },
      }),
      "n",
      "<M-F4>"
    )
    eq(real.origin, "other", "while the same content from a real file stays the user's")
    vim.keymap.del("n", "<M-F1>")
    vim.keymap.del("n", "<M-F4>")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.keymap.set("n", "<M-F5>", noop, { buffer = buf, desc = "local" })
    eq(find(rt.snapshot(), "n", "<M-F5>"), nil, "buffer-local mappings are not listed by default")
    local with = rt.snapshot({ buffers = true })
    local hit
    for _, m in ipairs(with) do
      if m.key == "<M-F5>" then
        hit = m
      end
    end
    ok(hit ~= nil and hit.buffer == buf, "but are, with buffers = true, tagged with their buffer")
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.keymap.del("n", "<M-F7>")
    vim.keymap.del("n", "<M-F6>")
  end

  -- -------------------------------------------------------- diff_defaults
  --
  -- Synthetic tables: a default that is overridden, one that was removed, one
  -- left alone, and a live mapping that is simply new.

  do
    local function def(mode, lhs, rhs, desc)
      return {
        mode = mode,
        lhs = lhs,
        key = lhs,
        rhs = rhs,
        desc = desc,
        callback = false,
        origin = "builtin",
      }
    end
    local pristine = {
      def("n", "Y", "y$", "yank line"),
      def("n", "]b", ":bnext<CR>", ":bnext"),
      def("n", "gx", ":Open<CR>", "open"),
      def("n", "[b", ":bprev<CR>", ":bprev"),
    }
    local live = {
      -- unchanged (same content, still the builtin)
      def("n", "]b", ":bnext<CR>", ":bnext"),
      -- overridden by a user mapping with a different target
      {
        mode = "n",
        lhs = "gx",
        key = "gx",
        rhs = ":MyOpen<CR>",
        callback = false,
        origin = "other",
        source = "init.lua",
        lnum = 3,
      },
      -- overridden although the content is identical: someone re-bound it
      {
        mode = "n",
        lhs = "[b",
        key = "[b",
        rhs = ":bprev<CR>",
        desc = ":bprev",
        callback = false,
        origin = "other",
      },
      -- new, not a default at all
      {
        mode = "n",
        lhs = "<M-F4>",
        key = "<M-F4>",
        rhs = ":x<CR>",
        callback = false,
        origin = "other",
      },
      -- buffer-local on a default's key: shadows, does not replace
      {
        mode = "n",
        lhs = "Y",
        key = "Y",
        rhs = ":local<CR>",
        callback = false,
        origin = "other",
        buffer = 3,
      },
    }
    local d = rt.diff_defaults(pristine, live)
    eq(#d.removed, 1, "one default is gone")
    eq(d.removed[1].key, "Y", "the one nobody binds globally any more")
    eq(#d.overridden, 2, "two defaults now do something else")
    eq(
      d.overridden[1].default.key,
      "[b",
      "(sorted) the re-bound one: origin is not builtin any more"
    )
    eq(d.overridden[2].default.key, "gx", "and the one with a new target")
    eq(d.overridden[2].live.rhs, ":MyOpen<CR>", "carrying the live entry")
    eq(d.unchanged, 1, "one is untouched")

    -- <Plug> wiring of a bundled plugin is not a key anyone presses.
    local with_plug = rt.diff_defaults({ def("n", "<Plug>(MatchitNormalForward)", ":x<CR>") }, {})
    eq(#with_plug.removed, 0, "a missing <Plug> default is not reported as removed")

    local clean = rt.diff_defaults(pristine, pristine)
    eq(#clean.overridden + #clean.removed, 0, "pristine against itself is no difference")
    eq(clean.unchanged, 4, "all unchanged")

    -- Changing only the description counts, for entries without an origin.
    local plain = rt.diff_defaults(
      { { mode = "n", lhs = "q", rhs = "x", desc = "a" } },
      { { mode = "n", lhs = "q", rhs = "x", desc = "b" } }
    )
    eq(#plain.overridden, 1, "a different description alone is a change")

    local lines = table.concat(rt.defaults_lines(d, { version = "0.0.0", total = 4 }), "\n")
    ok(
      lines:find("overridden", 1, true) ~= nil and lines:find(":MyOpen<CR>", 1, true) ~= nil,
      "the report names what it is now"
    )
    ok(
      lines:find("removed", 1, true) ~= nil and lines:find("yank line", 1, true) ~= nil,
      "and what was removed"
    )
  end

  -- ----------------------------------------------------- action_duplicates

  do
    local function m(mode, lhs, rhs, desc, extra)
      return vim.tbl_extend("force", {
        mode = mode,
        lhs = lhs,
        key = lhs,
        rhs = rhs,
        desc = desc,
        callback = rhs == nil,
        origin = "other",
      }, extra or {})
    end
    local live = {
      m("n", "<leader>a", nil, "[files] Open file"),
      m("n", "<leader>b", nil, "files: open file"),
      m("n", "<leader>c", nil, "Other thing"),
      m("n", "<leader>d", ":Foo<CR>"),
      m("n", "<leader>e", ":Foo<CR>"),
      m("x", "<leader>a", nil, "Open file"),
      m("n", "<leader>n", "<Nop>"),
      m("n", "<leader>o", "<Nop>"),
      m("n", "<leader>l", nil, "Local thing", { buffer = 1 }),
      m("n", "<leader>m", nil, "Local thing"),
      m("n", "gx", ":Open<CR>", "open", { origin = "builtin" }),
      m("n", "gX", ":Open<CR>", "open", { origin = "builtin" }),
    }
    local c = rt.action_duplicates(live)
    local by_kind = { desc = {}, rhs = {} }
    for _, g in ipairs(c) do
      by_kind[g.kind][#by_kind[g.kind] + 1] = g
    end
    eq(#by_kind.desc, 1, "one description is shared by several keys, decorations ignored")
    eq(by_kind.desc[1].value, "open file", "normalized")
    eq(#by_kind.desc[1].entries, 2, "by the two normal-mode keys, not the visual one")
    eq(#by_kind.rhs, 1, "one target is shared")
    eq(by_kind.rhs[1].value, ":Foo<CR>", "the same string rhs")
    eq(#c, 2, "<Nop>, other modes, other scopes and Neovim's own defaults give no candidate")

    local with_builtin = rt.action_duplicates(live, { builtin = true })
    ok(#with_builtin > #c, "Neovim's defaults can be asked for")

    eq(#rt.action_duplicates({}), 0, "nothing live, nothing duplicated")
    ok(rt.duplicate_lines(c)[1]:find("2 candidate", 1, true) ~= nil, "the report counts them")
  end

  -- ------------------------------------------------------ pristine_defaults

  do
    local pristine, err = rt.pristine_defaults({ refresh = true })
    if not pristine then
      -- No child process here: say so, loudly. A skip proves nothing.
      H.skipped("pristine_defaults", "cannot start a child Neovim: " .. tostring(err))
    else
      ok(#pristine > 0, "a clean Neovim has default mappings (" .. #pristine .. ")")
      for _, e in ipairs(pristine) do
        eq(e.origin, "builtin", "they are all defaults")
        eq(type(e.key), "string", "each with a comparable key")
      end

      local again = rt.pristine_defaults()
      eq(#again, #pristine, "the second call is answered from the cache")

      -- Against the live state of the test process: whatever differs is
      -- reported, nothing raises, and a default we remove shows up.
      local before = rt.diff_defaults(pristine, rt.snapshot())
      -- A default this very process has too (a bare `-u NONE` run loads no
      -- plugins, so the runtime plugins' own mappings may be missing here).
      local victim, saved
      for _, e in ipairs(pristine) do
        if e.mode == "n" and e.rhs then
          local m = vim.fn.maparg(e.lhs, "n", false, true)
          if m.lhs ~= nil and m.buffer == 0 then
            victim, saved = e, m
            break
          end
        end
      end
      if victim and saved then
        pcall(vim.keymap.del, "n", victim.lhs)
        local after = rt.diff_defaults(pristine, rt.snapshot())
        eq(#after.removed, #before.removed + 1, "deleting a default adds one removed entry")
        vim.keymap.set("n", victim.lhs, noop, { desc = "changed by the spec" })
        local again2 = rt.diff_defaults(pristine, rt.snapshot())
        eq(#again2.removed, #before.removed, "and re-binding it makes that an override instead")
        eq(#again2.overridden, #before.overridden + 1, "counted as overridden")
        -- Put Neovim's own default back: the runner shares this instance.
        pcall(vim.keymap.del, "n", victim.lhs)
        vim.fn.mapset("n", false, saved)
        local restored = rt.diff_defaults(pristine, rt.snapshot())
        eq(#restored.removed, #before.removed, "the default is restored for the specs that follow")
      else
        H.skipped("remove/override a default", "no suitable default mapping in this Neovim")
      end
    end
  end

  do
    local bad = rt.pristine_defaults({ timeout = 1, refresh = true })
    -- Either it answered inside a millisecond (a fast machine) or it reports a failure: never raises.
    ok(bad == nil or #bad > 0, "a timeout is a nil result, not an exception")
    rt.pristine_defaults({ refresh = true })
  end

  -- ------------------------------------------------------------- commands

  do
    keymap.create_usercmd("LibKeymapConflictsSpec", "LibKeymapRuntimeSpec")
    local cmds = vim.api.nvim_get_commands({})
    ok(cmds.LibKeymapConflictsSpec ~= nil, "the conflicts command exists")
    eq(cmds.LibKeymapConflictsSpec.bang, true, "and takes a bang for the full check")
    ok(cmds.LibKeymapRuntimeSpec ~= nil, "the runtime command exists")
    eq(cmds.LibKeymapRuntimeSpec.nargs, "?", "with an optional report name")
    local lines = keymap.runtime_lines("duplicates")
    ok(#lines > 0, "runtime_lines('duplicates') answers")
    ok(
      keymap.runtime_lines("nonsense")[1]:find("unknown report", 1, true) ~= nil,
      "an unknown report is a line, not an error"
    )
    local def = keymap.runtime_lines("defaults")
    ok(#def > 0, "runtime_lines() answers")
    vim.api.nvim_del_user_command("LibKeymapConflictsSpec")
    vim.api.nvim_del_user_command("LibKeymapRuntimeSpec")
  end
end
