-- TESTS/notify_popup_spec.lua — lib.nvim.notify.popup: toast delivery, history,
-- vim.notify fallback, and the `popup` option of notify.create.

return function(H)
  local eq, ok = H.eq, H.ok
  local popup = require("lib.nvim.notify.popup")
  popup.clear()

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

  -- No toast available: falls back to vim.notify, still records history.
  local native = {}
  local original = vim.notify
  vim.notify = function(msg, level)
    native[#native + 1] = { msg = msg, level = level }
  end
  with_stubs(
    {
      ["ui.notify"] = false,
      ["ui.kit.toast"] = {
        open = function()
          error("no ui")
        end,
      },
    },
    function()
      popup.deliver("first\nsecond", vim.log.levels.ERROR, { source = "spec" })
    end
  )
  vim.notify = original
  eq(#popup.history(), 1, "recorded in the history")
  eq(popup.history()[1].message, "first\nsecond", "verbatim")
  eq(#native, 1, "falls back to vim.notify when no toast can be shown")

  -- Toast path: wrapped, capped, titled with source and level.
  local opened
  with_stubs({
    ["ui.notify"] = {
      is_enabled = function()
        return false
      end,
    },
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver(("word "):rep(60), vim.log.levels.WARN, { source = "spec" })
    ok(opened, "toast is used")
    ok(#opened.message > 1, "long text is wrapped")
    for _, line in ipairs(opened.message) do
      ok(vim.fn.strdisplaywidth(line) <= 38, "wrapped lines fit")
    end
    eq(opened.title, "spec warn", "title carries source and level")

    popup.deliver(("x\n"):rep(40), vim.log.levels.ERROR)
    eq(#opened.message, 12, "very long text is capped")
  end)

  -- ui.notify active: no second popup, vim.notify handles it.
  native = {}
  opened = nil
  vim.notify = function(msg)
    native[#native + 1] = msg
  end
  with_stubs({
    ["ui.notify"] = {
      is_enabled = function()
        return true
      end,
    },
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    popup.deliver("via ui.notify", vim.log.levels.INFO)
  end)
  vim.notify = original
  eq(opened, nil, "no toast when ui.notify already handles vim.notify")
  eq(native[1], "via ui.notify", "handed to vim.notify")

  -- Source filtering.
  eq(#popup.history("spec"), 2, "history filters by source")
  popup.clear("spec")
  eq(#popup.history(), 2, "clear(source) keeps other sources")
  popup.clear()
  eq(#popup.history(), 0, "clear() forgets everything")

  -- notify.create({ popup = true }) routes through deliver with the prefix.
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function(o)
        opened = o
        return {}
      end,
    },
  }, function()
    local n = require("lib.nvim.notify").create("[spec]", { popup = true, source = "spec" })
    n.error("boom")
    eq(popup.history("spec")[1].message, "[spec] boom", "prefixed message recorded")
    eq(opened.title, "spec error", "level reflected")
  end)
  popup.clear()

  -- :messages: written by default, off by option, and never displayed via a
  -- native echo (no more-prompt).
  local function hist_has(text)
    return vim.api.nvim_exec2("messages", { output = true }).output:find(text, 1, true) ~= nil
  end
  vim.cmd("messages clear")
  with_stubs({
    ["ui.notify"] = false,
    ["ui.kit.toast"] = {
      open = function()
        return {}
      end,
    },
  }, function()
    popup.deliver("history line one\nline two", vim.log.levels.ERROR, { source = "spec" })
    ok(hist_has("history line one"), "written to :messages by default")

    vim.cmd("messages clear")
    popup.deliver("quiet message", vim.log.levels.INFO, { source = "spec", messages = false })
    ok(not hist_has("quiet message"), "per-call messages = false skips :messages")

    popup.setup({ messages = false })
    popup.deliver("global off", vim.log.levels.INFO)
    ok(not hist_has("global off"), "setup({ messages = false }) changes the default")
    popup.deliver("call wins", vim.log.levels.INFO, { messages = true })
    ok(hist_has("call wins"), "a per-call value beats the module default")
    popup.setup({ messages = true })
  end)
  popup.clear()
end
