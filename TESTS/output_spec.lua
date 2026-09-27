-- TESTS/output_spec.lua — lib.nvim.output: the create(prefix, opts) facade,
-- its channels (popup/echo/vim_notify), register_channel, and the headless
-- (#vim.api.nvim_list_uis() == 0) fallback that this very test runner
-- naturally exercises.

return function(H)
  local eq, ok = H.eq, H.ok
  local output = require("lib.nvim.output")

  local function with_stubs(stubs, fn)
    local saved = {}
    for name, mod in pairs(stubs) do
      saved[name] = package.loaded[name]
      package.loaded[name] = mod
    end
    local good, err = pcall(fn)
    for name in pairs(stubs) do
      package.loaded[name] = saved[name]
    end
    if not good then
      error(err, 0)
    end
  end

  -- This test runner is itself headless (nvim --headless, no UI attached), so
  -- create() without faking a UI exercises the real fallback: every channel
  -- becomes a plain io.stderr write, regardless of `opts.channel`.
  do
    local written = {}
    local fake_stderr = {
      write = function(_self, ...)
        written[#written + 1] = table.concat({ ... })
      end,
    }
    H.with_patched(io, "stderr", fake_stderr, function()
      local out = output.create("[spec]", { channel = "popup" })
      out.info("headless info")
      out.dump({ "a", "b" }, "title")
    end)
    ok(
      table.concat(written):find("headless info", 1, true) ~= nil,
      "headless fallback: info() writes to stderr"
    )
    ok(
      table.concat(written):find("title", 1, true) ~= nil,
      "headless fallback: dump() writes the title"
    )
    ok(
      table.concat(written):find("a", 1, true) ~= nil,
      "headless fallback: dump() writes the lines"
    )
  end

  -- Everything below simulates an attached UI so the real channels run.
  local function with_ui(fn)
    H.with_patched(vim.api, "nvim_list_uis", function()
      return { {} }
    end, fn)
  end

  -- Default channel (no `channel` given) is "popup": routes through
  -- lib.nvim.notify.popup, not a plain vim.notify() call.
  with_ui(function()
    local original_notify = vim.notify
    vim.notify = function()
      error("must not fall back to plain vim.notify when a toast can be shown")
    end
    with_stubs({
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          return {}
        end,
      },
    }, function()
      local out = output.create("[spec]", { source = "out-spec" })
      out.error("boom")
    end)
    vim.notify = original_notify
    eq(
      require("lib.nvim.notify.popup").history("out-spec")[1].message,
      "[spec] boom",
      "default channel delivers via lib.nvim.notify.popup"
    )
    require("lib.nvim.notify.popup").clear("out-spec")
  end)

  -- channel = "echo": routes through lib.nvim.echo.write, prefixed, no popup.
  with_ui(function()
    local seen
    with_stubs({
      ["lib.nvim.echo"] = {
        write = function(text, opts)
          seen = { text = text, opts = opts }
        end,
      },
    }, function()
      local out = output.create("[echo-spec]", { channel = "echo" })
      out.warn("12/128")
    end)
    eq(seen.text, "[echo-spec] 12/128", "echo channel prefixes the message")
    eq(seen.opts.level, vim.log.levels.WARN, "echo channel forwards the level")
  end)

  -- channel = "vim_notify": plain lib.nvim.notify.create(prefix), no popup.
  with_ui(function()
    local native
    local original_notify = vim.notify
    vim.notify = function(msg)
      native = msg
    end
    local out = output.create("[vn-spec]", { channel = "vim_notify" })
    out.info("plain")
    vim.notify = original_notify
    eq(native, "[vn-spec] plain", "vim_notify channel goes through plain vim.notify")
  end)

  -- dump(): identical viewer call regardless of channel.
  with_ui(function()
    local function seen_open(channel)
      local seen
      with_stubs({
        ["lib.nvim.ui.kit.viewer"] = {
          open = function(o)
            seen = o
            return {}
          end,
        },
        ["ui.notify"] = false,
        ["ui.kit.toast"] = {
          open = function()
            return {}
          end,
        },
      }, function()
        output.create("[dump-spec]", { channel = channel }).dump({ "l1", "l2" }, "my title")
      end)
      return seen
    end

    for _, channel in ipairs({ "popup", "echo", "vim_notify" }) do
      local seen = seen_open(channel)
      eq(seen.title, "my title", ("dump() opens the viewer with the title (%s)"):format(channel))
      eq(#seen.lines, 2, ("dump() opens the viewer with the lines (%s)"):format(channel))
    end
  end)

  -- register_channel: a caller-supplied channel is resolved by name, exactly
  -- like the three built-in ones.
  with_ui(function()
    local created_prefix, created_opts
    output.register_channel("test-channel", function(prefix, create_opts)
      created_prefix, created_opts = prefix, create_opts
      return {
        notify = function() end,
        info = function() end,
        warn = function() end,
        error = function() end,
        debug = function() end,
        dump = function() end,
      }
    end)
    output.create("[reg-spec]", { channel = "test-channel", source = "x" })
    eq(created_prefix, "[reg-spec]", "register_channel's factory receives the prefix")
    eq(created_opts.source, "x", "register_channel's factory receives the create opts")
  end)

  -- Unknown channel: a clear error, not a silent fallback.
  with_ui(function()
    ok(
      not pcall(output.create, "[bad]", { channel = "does-not-exist" }),
      "an unregistered channel name raises instead of silently defaulting"
    )
  end)
end
