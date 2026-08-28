-- TESTS/hover_registry_spec.lua — lib.nvim.hover's provider registry, and the
-- degradation guarantees that depend on it.
--
-- The registry is what let the hover framework move out of markdown.nvim: it
-- is the only channel through which plugin-specific knowledge reaches a
-- library that must work with none of those plugins installed. So what is
-- asserted here is mostly the *absence* of coupling — that nothing crashes,
-- and nothing is attached, when a plugin is missing.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local registry = require("lib.nvim.hover.registry")
  local hover = require("lib.nvim.hover")

  registry.reset()

  -- ── Nothing registered: the library still stands on its own ──────────────
  ok(not registry.has_sources(), "no contribution means no sources")
  eq(registry.source_at(0, 1, 0), nil, "…and asking for one yields nil, not an error")
  eq(registry.preview_for("image"), nil, "…nor is any preview claimed")

  -- ── A source is asked, and its extra fields survive ──────────────────────
  registry.register("fake.nvim", {
    sources = {
      function(_, row, col)
        if row == 1 and col == 3 then
          return "target.png", { kind = "fake", col = 3, col_end = 9 }
        end
        return nil
      end,
    },
    previews = {
      image = function()
        return { lines = { "claimed" } }
      end,
    },
  })

  ok(registry.has_sources(), "a registered source is visible")
  local target, extra = registry.source_at(0, 1, 3)
  eq(target, "target.png", "the source's target comes back")
  eq(extra and extra.kind, "fake", "…along with the fields it wanted carried")
  eq(registry.source_at(0, 2, 0), nil, "a position the source declines yields nil")
  ok(registry.preview_for("image") ~= nil, "a claimed type reports its preview")
  eq(registry.preview_for("pdf"), nil, "…and an unclaimed one does not")

  -- ── Re-registering replaces rather than stacks ───────────────────────────
  -- setup() running twice (a reload, :Lazy reload) must not make every source
  -- fire twice -- which for a source that side-effects would be a real bug,
  -- and for the ordering guarantee is one regardless.
  local calls = 0
  for _ = 1, 3 do
    registry.register("fake.nvim", {
      sources = {
        function()
          calls = calls + 1
          return nil
        end,
      },
    })
  end
  registry.source_at(0, 1, 0)
  eq(calls, 1, "three registrations under one name leave exactly one source")

  -- ── A broken contribution does not take the hover down ───────────────────
  registry.register("broken.nvim", {
    sources = {
      function()
        error("this plugin is having a bad day")
      end,
    },
  })
  registry.register("good.nvim", {
    sources = {
      function()
        return "still-works.md"
      end,
    },
  })
  local survived = registry.source_at(0, 1, 0)
  eq(survived, "still-works.md", "a source that errors is skipped, later ones still run")

  -- ── attach(): nothing installed that could answer -> no autocmd ──────────
  -- The reason this matters: lib.nvim is a dependency, so it is routinely
  -- present with none of its consumer plugins. A user who installs only
  -- lib.nvim must not pay for a CursorHold autocmd that can never show
  -- anything.
  do
    registry.reset()
    local buf = vim.api.nvim_create_buf(false, false) -- a real (buftype "") buffer
    vim.api.nvim_set_current_buf(buf)

    local function hover_autocmds()
      local n = 0
      for _, a in ipairs(vim.api.nvim_get_autocmds({ event = "CursorHold", buffer = buf })) do
        if (a.desc or ""):match("lib%.nvim%.hover") then
          n = n + 1
        end
      end
      return n
    end

    hover.setup({ bare_paths = false })
    hover.attach(buf)
    eq(hover_autocmds(), 0, "no sources and no bare paths: nothing is attached")

    -- Bare paths alone are reason enough -- they need no plugin at all.
    hover.setup({ bare_paths = true })
    hover.attach(buf)
    ok(hover_autocmds() > 0, "bare paths alone justify attaching")

    -- A non-file buffer never gets one, whatever is registered.
    local scratch = vim.api.nvim_create_buf(false, true) -- buftype = "nofile"
    vim.api.nvim_set_current_buf(scratch)
    hover.attach(scratch)
    local n = 0
    for _, a in ipairs(vim.api.nvim_get_autocmds({ event = "CursorHold", buffer = scratch })) do
      if (a.desc or ""):match("lib%.nvim%.hover") then
        n = n + 1
      end
    end
    eq(n, 0, "a non-file buffer (picker, tree, terminal) is never attached to")

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.api.nvim_buf_delete, scratch, { force = true })
  end

  -- ── The framework works with no plugin providers at all ──────────────────
  -- classify and the text previews must not reach for images.nvim/pdfport/
  -- markdown.nvim to answer; an image without a drawing provider still gets a
  -- description rather than an error.
  do
    registry.reset()
    local classify = require("lib.nvim.hover.classify")
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local f = tmp .. "/plain.txt"
    vim.fn.writefile({ "alpha", "beta" }, f)

    local t = classify.classify("plain.txt", tmp .. "/doc.md")
    eq(t.type, "file", "classify works with nothing registered")

    local content = require("lib.nvim.hover.preview.text").file(t, { max_lines = 10 })
    eq(content.lines[1], "alpha", "…and the file preview does too")

    vim.fn.delete(tmp, "rf")
  end

  -- ── scrolling a text preview ─────────────────────────────────────────────
  -- The offset half of `lib.nvim.hover.scroll`. The keymap lifecycle needs a
  -- live float and is exercised by hand; what is pinned here is the part that
  -- decides whether keys get bound at all -- `scroll.more` -- and that
  -- overshooting the end falls back rather than showing an empty float.
  do
    local text = require("lib.nvim.hover.preview.text")
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")

    local long = tmp .. "/long.txt"
    local rows = {}
    for i = 1, 60 do
      rows[i] = "line " .. i
    end
    vim.fn.writefile(rows, long)
    local doc = { type = "file", raw = "long.txt", path = long }

    local first = text.file(doc, { max_lines = 10 })
    eq(first.lines[1], "line 1", "scroll: unscrolled preview starts at the top")
    ok(first.scroll.more, "scroll: a file longer than the float reports more to come")
    eq(first.scroll.offset, 0, "scroll: ...at offset 0")

    local second = text.file(doc, { max_lines = 10, offset = 10 })
    eq(second.lines[1], "line 11", "scroll: an offset skips exactly that many lines")
    ok(second.title:match("10") ~= nil, "scroll: the title says how far down it is")

    local last = text.file(doc, { max_lines = 10, offset = 55 })
    eq(last.lines[#last.lines], "line 60", "scroll: the final window reaches the last line")
    ok(not last.scroll.more, "scroll: ...and reports nothing follows")

    -- Overshooting must not produce an empty float: it falls back to the last
    -- readable window, which is what a shrinking file would otherwise cause.
    local past = text.file(doc, { max_lines = 10, offset = 999 })
    ok(#past.lines > 0, "scroll: overshooting the end still shows content")
    ok(past.scroll.offset < 999, "scroll: ...having fallen back to a real offset")

    -- A file that fits is not scrollable, so no keys should ever be bound.
    local short = tmp .. "/short.txt"
    vim.fn.writefile({ "a", "b" }, short)
    local fits = text.file({ type = "file", raw = "short.txt", path = short }, { max_lines = 10 })
    ok(not fits.scroll.more, "scroll: a file that fits reports nothing to scroll")

    vim.fn.delete(tmp, "rf")
  end

  registry.reset()
end
