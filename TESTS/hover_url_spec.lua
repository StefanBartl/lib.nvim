-- TESTS/hover_url_spec.lua — the web hover: what counts as a URL under the
-- cursor, and the switch that decides whether any of it opens a float.
--
-- Two things are pinned here, and they fail in opposite directions.
--
--   * **The switch.** Documentation is made of links. With the web hover on
--     by default, resting the cursor anywhere in a line of prose opens a
--     float over the text being read. `url.hover` is off unless asked for,
--     and it has to gate *both* routes a URL arrives by — a markdown link
--     scanner's target and a bare URL in plain text — or the switch only
--     half works, in whichever filetype nobody tested.
--   * **The finding.** A URL is found by shape, on the line, and not through
--     `<cfile>`: that one stops at whatever `'isfname'` excludes, which is
--     how `?query=` and `#fragment` used to get cut off. The cases below are
--     the ones prose actually produces — a URL in parentheses, a URL ending a
--     sentence, a Wikipedia URL that closes its own bracket, and a Windows
--     path in a string literal that is not a URL at all.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local api = vim.api
  local classify = require("lib.nvim.hover.classify")
  local bare_url = require("lib.nvim.hover.bare_url")
  local url_preview = require("lib.nvim.hover.preview.url")
  local hover = require("lib.nvim.hover")
  local float = require("lib.nvim.hover.float")

  -- Written this way rather than as an escape, because a spec is also read by
  -- whoever has to fix it, and `"\\\\"` in a line about backslashes is one
  -- ambiguity too many.
  local BS = string.char(92)

  -- ── Classification ─────────────────────────────────────────────────────

  eq(classify.classify("https://example.com/a", nil).type, "url", "an https target is a url")
  eq(
    classify.classify("www.example.com", nil).url,
    "https://www.example.com",
    "a bare host gets the scheme a browser would give it"
  )
  eq(
    classify.classify("http:" .. BS .. BS .. "example.com", nil).url,
    "http://example.com",
    "the Windows-keyboard typo is repaired rather than shown as garbage"
  )
  eq(
    classify.classify("http:" .. BS .. "example.com", nil).url,
    "http://example.com",
    "one backslash too"
  )
  eq(
    classify.classify("mailto:me@example.com", nil).url,
    "mailto:me@example.com",
    "mailto has no separator and must not grow one"
  )

  -- ── Finding one on a line ──────────────────────────────────────────────

  ---@param line string
  ---@return string[]
  local function urls(line)
    local out = {}
    for _, span in ipairs(bare_url.spans(line)) do
      out[#out + 1] = span.url
    end
    return out
  end

  eq(
    urls("see https://neovim.io/doc?a=b#c now")[1],
    "https://neovim.io/doc?a=b#c",
    "query and fragment survive"
  )
  eq(
    urls("(https://example.com), and more")[1],
    "https://example.com",
    "a wrapping paren is not part of it"
  )
  eq(
    urls("ends the sentence https://example.com.")[1],
    "https://example.com",
    "nor is the full stop"
  )
  eq(
    urls("https://en.wikipedia.org/wiki/Vim_(text_editor) is the page")[1],
    "https://en.wikipedia.org/wiki/Vim_(text_editor)",
    "a bracket the URL opened itself is kept"
  )
  eq(
    #urls('local p = "C:' .. BS .. BS .. "Users" .. BS .. BS .. 'me.lua"'),
    0,
    "a Windows path in a string literal is not a URL"
  )
  eq(#urls("and/or, 60% / 27%, nothing here"), 0, "prose with separators is not a URL")
  eq(
    urls("write to mailto:me@example.com, please")[1],
    "mailto:me@example.com",
    "mailto, comma trimmed"
  )
  eq(
    #urls("http:" .. BS .. BS .. "www.example.com only"),
    1,
    "the typo'd URL is found once, not once per pattern that matches part of it"
  )

  -- ── The offline preview ────────────────────────────────────────────────

  local parsed = url_preview.offline(classify.classify("https://example.com/a/b?q=x%20y", nil))
  eq(parsed.lines[1], "example.com", "host first")
  eq(parsed.lines[2], "/a/b", "then the path")
  ok(parsed.lines[3]:match("q=x y"), "and the query, percent-decoded: " .. parsed.lines[3])

  -- ── The switch, through the real entry point ───────────────────────────

  local win = api.nvim_get_current_win()
  local prev_buf = api.nvim_win_get_buf(win)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "see https://example.com/a for details" })
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_set_cursor(win, { 1, 10 }) -- inside the URL

  local saved_hover = hover.is_web_enabled()
  hover.setup({ url = { hover = false, fetch = false } })

  eq(hover.show({}), false, "web hover off: standing on a link shows nothing")
  eq(float.is_open(), false, "and no float was opened")

  eq(hover.show({ force = true }), true, "an explicit, forced show is the user asking for this one")
  hover.hide()

  hover.setup({ url = { hover = true } })
  eq(hover.show({}), true, "web hover on: the same position now resolves")
  ok(float.is_open(), "and the float is up")

  local shown = api.nvim_buf_get_lines(api.nvim_win_get_buf(float.win()), 0, -1, false)
  eq(shown[1], "example.com", "showing the parsed URL, with nothing fetched")

  hover.hide()
  hover.setup({ url = { hover = saved_hover } })
  api.nvim_win_set_buf(win, prev_buf)
  pcall(api.nvim_buf_delete, buf, { force = true })
end
