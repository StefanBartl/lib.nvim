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
