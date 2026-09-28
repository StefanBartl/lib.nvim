-- TESTS/progress_echo_style_spec.lua — lib.nvim.progress: the "echo" style
-- (resolve_style branch + the style's own start/update/finish/cancel
-- contract) and the style-list capability of progress.create({style = {...}}).

return function(H)
  local eq = H.eq

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

  -- resolve_style("echo") resolves to styles/echo.lua, same as every other
  -- named style (no soft-dependency check needed -- nvim_echo is core API).
  local resolve_style = require("lib.nvim.progress.resolve_style")
  eq(
    resolve_style("echo"),
    require("lib.nvim.progress.styles.echo"),
    'resolve_style("echo") returns styles/echo.lua'
  )

  -- The "echo" style's own contract: start/update write with history = false,
  -- finish/cancel write once with history = true.
  do
    local echo_style = require("lib.nvim.progress.styles.echo")
    local writes = {}
    with_stubs({
      ["lib.nvim.echo"] = {
        write = function(text, opts)
          writes[#writes + 1] = { text = text, opts = opts }
        end,
      },
    }, function()
      local spec = { title = "[p] ", text = "searching", current = 12, total = 128 }
      local state = echo_style.start(spec)
      eq(writes[1].text, "[p] searching (12/128)", "start() renders title/text/current/total")
      eq(writes[1].opts.history, false, "start() writes with history = false")

      state = echo_style.update(state, spec)
      eq(#writes, 2, "update() writes again")
      eq(writes[2].opts.history, false, "update() writes with history = false")

      echo_style.finish(state, { title = "[p] ", text = "done" })
      eq(writes[3].text, "[p] done", "finish() renders the final spec")
      eq(writes[3].opts.history, true, "finish() writes with history = true")

      echo_style.cancel(state, { title = "[p] ", text = "cancelled" })
      eq(writes[4].opts.history, true, "cancel() writes with history = true")
    end)
  end

  -- Style list: progress.create({style = {"statusline", "echo"}}) runs BOTH
  -- styles in parallel for the same handle -- two stubs, two call counts,
  -- same spec reaching each.
  do
    local calls = { statusline = 0, echo = 0 }
    local seen_spec = {}
    local function stub_style(name)
      return {
        start = function(spec)
          seen_spec[name] = spec
          return { name = name }
        end,
        update = function(state, spec)
          calls[name] = calls[name] + 1
          seen_spec[name] = spec
          return state
        end,
        finish = function()
          calls[name .. "_finish"] = (calls[name .. "_finish"] or 0) + 1
        end,
        cancel = function() end,
      }
    end

    with_stubs({
      ["lib.nvim.progress.styles.statusline"] = stub_style("statusline"),
      ["lib.nvim.progress.styles.echo"] = stub_style("echo"),
    }, function()
      local progress = require("lib.nvim.progress")
      local h = progress.create({ style = { "statusline", "echo" }, delay_ms = 0 })
      h:update({ text = "12/128" })
      eq(calls.statusline, 1, "the statusline style's update() ran")
      eq(calls.echo, 1, "the echo style's update() ran")
      eq(seen_spec.statusline.text, "12/128", "both styles receive the same spec (statusline)")
      eq(seen_spec.echo.text, "12/128", "both styles receive the same spec (echo)")

      h:finish("done")
      eq(calls.statusline_finish, 1, "the statusline style's finish() ran")
      eq(calls.echo_finish, 1, "the echo style's finish() ran")
    end)
  end

  -- Regression: one style raising in start/update/finish must not stop the
  -- OTHER styles in the list from ever rendering again -- a single
  -- misbehaving renderer (a third-party style, "float"/"kit" against an
  -- already-closed window) previously broke the whole handle for every
  -- other requested style too.
  do
    local calls = { echo = 0, echo_finish = 0 }
    -- Fails at start(): permanently disabled from that point on, so
    -- update()/finish() must skip it without ever calling it again.
    local broken_at_start = {
      start = function()
        error("boom: broken style start")
      end,
      update = function()
        error("must not be called: style failed at start()")
      end,
      finish = function()
        error("must not be called: style failed at start()")
      end,
      cancel = function() end,
    }
    local echo_stub = {
      start = function()
        return {}
      end,
      update = function(state)
        calls.echo = calls.echo + 1
        return state
      end,
      finish = function()
        calls.echo_finish = calls.echo_finish + 1
      end,
      cancel = function() end,
    }

    with_stubs({
      ["lib.nvim.progress.styles.statusline"] = broken_at_start,
      ["lib.nvim.progress.styles.echo"] = echo_stub,
    }, function()
      local progress = require("lib.nvim.progress")
      -- Neither start() failing (statusline) nor the whole create() call
      -- itself may raise: a broken style degrades, it doesn't crash the caller.
      local ok_create, h = pcall(progress.create, {
        style = { "statusline", "echo" },
        delay_ms = 0,
      })
      eq(ok_create, true, "a style raising in start() does not raise out of create()")

      local ok_update = pcall(function()
        h:update({ text = "x" })
      end)
      eq(ok_update, true, "the style that failed at start() is skipped, not retried, in update()")
      eq(calls.echo, 1, "the other style's update() still ran")

      local ok_finish = pcall(function()
        h:finish("done")
      end)
      eq(ok_finish, true, "the style that failed at start() is skipped, not retried, in finish()")
      eq(calls.echo_finish, 1, "the other style's finish() still ran")
    end)
  end

  -- Same guarantee, but the failure happens in update() (after a clean
  -- start()) -- must disable just that style from there on, without
  -- touching the other style's own update()/finish().
  do
    local calls = { echo = 0, echo_finish = 0 }
    local fail_count = 0
    local flaky_after_start = {
      start = function()
        return {}
      end,
      update = function()
        fail_count = fail_count + 1
        error("boom: broken style update")
      end,
      finish = function()
        error("must not be called: style failed at update()")
      end,
      cancel = function() end,
    }
    local echo_stub = {
      start = function()
        return {}
      end,
      update = function(state)
        calls.echo = calls.echo + 1
        return state
      end,
      finish = function()
        calls.echo_finish = calls.echo_finish + 1
      end,
      cancel = function() end,
    }

    with_stubs({
      ["lib.nvim.progress.styles.statusline"] = flaky_after_start,
      ["lib.nvim.progress.styles.echo"] = echo_stub,
    }, function()
      local progress = require("lib.nvim.progress")
      local h = progress.create({ style = { "statusline", "echo" }, delay_ms = 0 })

      pcall(function()
        h:update({ text = "x" })
      end)
      eq(fail_count, 1, "the flaky style's update() ran once and raised")
      eq(calls.echo, 1, "the other style's update() still ran")

      -- A second update() must not retry the now-disabled style.
      pcall(function()
        h:update({ text = "y" })
      end)
      eq(fail_count, 1, "a style that already failed once is not retried on a later update()")
      eq(calls.echo, 2, "the other style keeps updating normally")

      pcall(function()
        h:finish("done")
      end)
      eq(calls.echo_finish, 1, "the other style's finish() still runs after a sibling failed")
    end)
  end

  -- Backwards compatible: a bare string `style` (the pre-existing calling
  -- convention) still resolves to exactly one style, unchanged.
  do
    local calls = 0
    with_stubs({
      ["lib.nvim.progress.styles.notify"] = {
        start = function()
          return {}
        end,
        update = function(state)
          calls = calls + 1
          return state
        end,
        finish = function() end,
        cancel = function() end,
      },
    }, function()
      local progress = require("lib.nvim.progress")
      local h = progress.create({ style = "notify", delay_ms = 0 })
      h:update({ text = "x" })
      eq(calls, 1, "a bare string style still works exactly as before")
    end)
  end
end
