-- TESTS/hover_binary_spec.lua — what the hover does with a file that has no
-- text in it.
--
-- The bug this pins: hovering a `.docx` opened a float holding the first
-- twenty "lines" of a ZIP container — mojibake, with the document's own name
-- in the border, which reads as a preview rather than as garbage. Every
-- binary format did it, because a file preview reads lines and a binary file
-- contains newline bytes.
--
-- Two separate mechanisms have to keep working, and only one of them is a
-- list anyone maintains:
--
--   * office documents are classified as `office`, because they are the one
--     group with a second answer available (convert to PDF, show the page);
--   * everything else is caught by *looking at the bytes*, so a container
--     nobody listed gets the badge too. That is the half that matters, and
--     the half a test can lose silently.

---@param H table harness from TESTS/run.lua
return function(H)
  local eq, ok = H.eq, H.ok

  local classify = require("lib.nvim.hover.classify")
  local binary = require("lib.nvim.hover.preview.binary")
  local formats = require("lib.nvim.hover.formats")
  local text = require("lib.nvim.hover.preview.text")

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  --- Write `bytes` to `name` under the temp root and return the path.
  ---@param name string
  ---@param bytes string
  ---@return string
  local function write(name, bytes)
    local path = root .. "/" .. name
    local f = assert(io.open(path, "wb"))
    f:write(bytes)
    f:close()
    return path
  end

  -- A ZIP header plus a compressed-looking run of NULs: what every modern
  -- office document, and every jar/apk/epub, actually begins with.
  local container = "PK\3\4" .. string.rep("\0\1\2\3", 200)

  -- ── Classification ─────────────────────────────────────────────────────

  eq(classify.classify(write("report.docx", container), nil).type, "office", "docx is office")
  eq(classify.classify(write("sheet.xlsx", container), nil).type, "office", "xlsx is office")
  eq(classify.classify(write("deck.pptx", container), nil).type, "office", "pptx is office")
  eq(classify.classify(write("old.doc", container), nil).type, "office", "legacy .doc too")
  eq(classify.classify(write("open.odt", container), nil).type, "office", "odt is office")

  -- Not office: these have their own previews, and stealing them would trade
  -- a picture for a badge.
  eq(classify.classify(write("a.png", container), nil).type, "image", "png stays an image")
  eq(classify.classify(write("notes.md", "# hi\n"), nil).type, "markdown", "md stays markdown")

  -- An archive is *not* an office document — it gets the generic badge, not
  -- the conversion route, because LibreOffice has nothing to say about it.
  eq(classify.classify(write("src.zip", container), nil).type, "file", "zip is a plain file")
  eq(formats.is_office("zip"), false, "zip is not convertible")
  eq(formats.label("zip"), "ZIP archive", "and still has a name")

  -- ── The byte test, which is what covers the unlisted formats ───────────

  ok(binary.is_binary(write("thing.bin", container)), "NUL bytes mean binary")
  ok(
    binary.is_binary(write("unknown.qqq", string.rep("\0\255", 500))),
    "an extension nobody listed is still caught by its bytes"
  )
  eq(binary.is_binary(write("plain.txt", "hello\nworld\n")), false, "text is not binary")
  eq(
    binary.is_binary(write("umlaut.txt", "Grüße aus Wien\nzweite Zeile\n")),
    false,
    "UTF-8 prose is not binary"
  )
  eq(binary.is_binary(write("empty.txt", "")), false, "an empty file has nothing to misread")
  eq(
    binary.is_binary(write("tabs.txt", "a\tb\r\nc\f\v\n")),
    false,
    "tab/CR/FF/VT are text, and a table of them must not read as a container"
  )

  -- ── What the preview actually returns ──────────────────────────────────

  local zip = classify.classify(root .. "/src.zip", nil)
  local badge = text.file(zip, { max_lines = 20 })
  eq(badge.lines[1], "◆ ZIP archive", "the badge names the format")
  ok(badge.lines[2]:match("^ZIP · "), "and gives extension and size: " .. badge.lines[2])
  eq(badge.highlight, "LibHoverInfo", "a healthy file is not an error")
  eq(badge.scroll, nil, "nothing to scroll, so no keys are borrowed")

  local plain = classify.classify(root .. "/plain.txt", nil)
  eq(text.file(plain, { max_lines = 20 }).lines[1], "hello", "a text file still shows its head")

  -- ── The office preview with the conversion switched off ────────────────

  local office = require("lib.nvim.hover.preview.office")
  local docx = classify.classify(root .. "/report.docx", nil)
  local called = false
  local content = office.preview(docx, { max_lines = 20, office_convert = false }, function()
    called = true
  end)

  eq(content.lines[1], "◆ Word document", "off means a badge, not mojibake")
  eq(content.pending, nil, "and nothing is pending: no work was started")
  eq(called, false, "no callback, no conversion, no LibreOffice")
  ok(
    content.lines[#content.lines]:match(":Lib hover office on"),
    "the badge says what can be done about it: " .. content.lines[#content.lines]
  )

  vim.fn.delete(root, "rf")
end
