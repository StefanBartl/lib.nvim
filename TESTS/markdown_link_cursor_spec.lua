-- TESTS/markdown_link_cursor_spec.lua — lib.nvim.markdown.link_cursor
--
-- The rule: go where something is still missing. Empty title -> inside the
-- brackets; filled title -> the path; the first link of several decides.

return function(H)
  local eq, ok = H.eq, H.ok
  local lc = require("lib.nvim.markdown.link_cursor")

  local function spot(text, opts)
    local s = lc.locate(text, opts)
    return s and (s.row .. ":" .. s.col .. ":" .. s.kind) or nil
  end

  -- ── locate: pure ──────────────────────────────────────────────────────────
  eq(spot("![](assets/x.png)"), "0:2:title", "image with empty alt: inside []")
  eq(spot("[](https://example.com)"), "0:1:title", "empty title + url: inside []")
  eq(spot("[]()"), "0:1:title", "empty title + empty path: title wins")
  eq(spot("[name](a/b.md)"), "0:13:path", "filled title + path: end of the path")
  eq(spot("[name](a/b.md)", { path_cursor = "start" }), "0:7:path", "path_cursor = start")
  eq(spot("[name]()"), "0:7:path", "filled title + empty path: inside ()")
  eq(spot("text [a](b) tail"), "0:10:path", "link in the middle of a line")
  eq(spot("no link here"), nil, "no link -> nil")
  eq(spot("[a](x)\n[b](y)"), "0:5:path", "first link decides")
  eq(spot({ "first line", "![](p.png)" }), "1:2:title", "link on a later line: row is relative")
  eq(
    spot("[](a)\n[b](c)"),
    "0:1:title",
    "an empty title on the first link beats a later filled one"
  )

  -- ── place / insert against a real buffer ──────────────────────────────────
  local function scratch(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf, vim.api.nvim_get_current_win()
  end
  local function cursor()
    local c = vim.api.nvim_win_get_cursor(0)
    return c[1] .. ":" .. c[2]
  end

  local buf, win = scratch({ "see  end" })
  ok(lc.insert(buf, win, 0, 4, "![](a.png)", { startinsert = false }), "insert reports ok")
  eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "see ![](a.png) end", "text inserted")
  eq(cursor(), "1:6", "cursor inside the empty alt text")

  buf, win = scratch({ "x" })
  lc.insert(buf, win, 0, 1, " [name](dir/f.md)", { startinsert = false })
  eq(cursor(), "1:17", "filled title: cursor at the end of the path")

  -- several links inserted as lines: the first one decides, row is offset
  buf, win = scratch({ "intro", "" })
  lc.insert(buf, win, 1, 0, { "[a](one.md)", "[b](two.md)" }, { startinsert = false })
  eq(cursor(), "2:10", "multi-line insertion: cursor in the first link's path")

  -- no link in the text: behind it, like before
  buf, win = scratch({ "ab" })
  lc.insert(buf, win, 0, 1, "ZZ", { startinsert = false })
  eq(cursor(), "1:3", "no link: cursor behind the inserted text")

  -- enable = false: behind the text even for a link
  buf, win = scratch({ "" })
  lc.insert(buf, win, 0, 0, "![](a.png)", { enable = false, startinsert = false })
  eq(cursor(), "1:9", "enable = false keeps the old cursor behavior")

  -- insert_links: one inline, several on lines of their own
  buf, win = scratch({ "prose here" })
  vim.api.nvim_win_set_cursor(win, { 1, 5 })
  ok(lc.insert_links(buf, win, { "[a](one.md)" }, { startinsert = false }), "one link: ok")
  eq(
    vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
    "prose[a](one.md) here",
    "one link goes inline at the cursor"
  )
  eq(cursor(), "1:15", "…cursor in its path")

  buf, win = scratch({ "prose here", "tail" })
  vim.api.nvim_win_set_cursor(win, { 1, 3 })
  lc.insert_links(buf, win, { "[a](one.md)", "[b](two.md)" }, { startinsert = false })
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|"),
    "prose here|[a](one.md)|[b](two.md)|tail",
    "several links go below a non-blank line, prose is never split"
  )
  eq(cursor(), "2:10", "…cursor in the FIRST link's path")

  buf, win = scratch({ "", "tail" })
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  lc.insert_links(buf, win, { "[](x.md)", "[b](two.md)" }, { startinsert = false })
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|"),
    "[](x.md)|[b](two.md)|tail",
    "several links replace a blank line"
  )
  eq(cursor(), "1:1", "…an empty first title gets the cursor")
  eq(lc.insert_links(buf, win, {}), false, "no links -> false")

  -- the window no longer shows the buffer the text went into (async insertion,
  -- the user moved on): nothing is placed, the cursor of that window is left alone
  do
    local b1, w1 = scratch({ "one" })
    local b2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "other buffer, a longer line" })
    vim.api.nvim_win_set_buf(w1, b2)
    vim.api.nvim_win_set_cursor(w1, { 1, 3 })
    ok(
      lc.insert(b1, w1, 0, 0, "![](a.png)", { startinsert = false }),
      "the text is still inserted into its own buffer"
    )
    eq(vim.api.nvim_buf_get_lines(b1, 0, 1, false)[1], "![](a.png)one", "…there")
    eq(
      vim.api.nvim_win_get_cursor(w1)[2],
      3,
      "…and the window now showing another buffer keeps its cursor"
    )
    eq(
      lc.place(w1, 0, 0, "[](x)", { startinsert = false }, b1),
      false,
      "place(…, buf) refuses a window showing another buffer"
    )
  end

  -- a non-modifiable buffer is refused, nothing throws
  buf, win = scratch({ "" })
  vim.bo[buf].modifiable = false
  eq(lc.insert(buf, win, 0, 0, "[](x)"), false, "not modifiable -> false")
  eq(lc.place(9999, 0, 0, "[](x)"), false, "invalid window -> false")

  -- module defaults: setup() changes them, per-call opts still win
  lc.setup({ path_cursor = "start", bogus = true })
  eq(lc.config().path_cursor, "start", "setup changes the default")
  eq(spot("[name](a/b.md)"), "0:7:path", "locate follows the default")
  eq(spot("[name](a/b.md)", { path_cursor = "end" }), "0:13:path", "per-call opts win")
  lc.setup({ path_cursor = "end", startinsert = true, enable = true })
  lc.setup({ path_cursor = "sideways", startinsert = "yes" })
  eq(lc.config().path_cursor, "end", "invalid setup values are ignored")

  -- insert mode: a headless `-l` run never returns to the main loop, where
  -- `:startinsert` would take effect, so assert the command is issued instead.
  local issued = {}
  local real_cmd = vim.cmd
  vim.cmd = function(c)
    issued[#issued + 1] = c
  end
  buf, win = scratch({ "" })
  lc.insert(buf, win, 0, 0, "![](a.png)")
  lc.insert(buf, win, 0, 0, "plain text")
  lc.insert(buf, win, 0, 0, "![](b.png)", { startinsert = false })
  vim.cmd = real_cmd
  eq(#issued, 1, "startinsert only for a link, and only when not switched off")
  eq(issued[1], "startinsert", "the command is startinsert")
end
