-- TESTS/harvest_spec.lua — lib.nvim.harvest.{scope,render,sink,emit}

return function(H)
  local eq, ok = H.eq, H.ok

  local harvest = require("lib.nvim.harvest")
  local scope = harvest.scope
  local render = harvest.render

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  local function write_raw(path, content)
    local f = assert(io.open(path, "wb"), "harvest spec: must be able to write " .. path)
    f:write(content)
    f:close()
  end

  -- ------------------------------------------------------------- scope.resolve

  -- "path" on a single file: reads it whole, `first` == 1.
  local plain = dir .. "/plain.md"
  write_raw(plain, "line one\nline two\nline three")
  local srcs = scope.resolve("path", { path = plain })
  eq(#srcs, 1, "scope.resolve(path): single file yields one source")
  eq(#srcs[1].lines, 3, "scope.resolve(path): all lines read")
  eq(srcs[1].first, 1, "scope.resolve(path): first is 1 for a whole-file read")

  -- CRLF normalization: \r\n collapses to a plain line, no stray \r survives,
  -- and a trailing newline does not produce a phantom final empty line.
  local crlf = dir .. "/crlf.txt"
  write_raw(crlf, "alpha\r\nbeta\r\ngamma\r\n")
  local crlf_srcs = scope.resolve("path", { path = crlf })
  local crlf_lines = crlf_srcs[1].lines
  eq(#crlf_lines, 3, "scope.resolve: trailing newline does not add a phantom 4th line")
  eq(crlf_lines[1], "alpha", "scope.resolve: CRLF normalized, no stray \\r")
  eq(crlf_lines[3], "gamma", "scope.resolve: last real line intact after CRLF normalization")

  -- Binary detection: a NUL byte anywhere in the file marks it unreadable as
  -- text, both for a direct single-file path and inside a directory scan.
  local bin = dir .. "/blob.bin"
  write_raw(bin, "PNG\0\1\2\3")
  local _, bin_err = scope.resolve("path", { path = bin })
  ok(bin_err ~= nil, "scope.resolve(path): a NUL-containing file reports an error")

  local bindir = dir .. "/bindir"
  vim.fn.mkdir(bindir, "p")
  write_raw(bindir .. "/a.txt", "text file")
  write_raw(bindir .. "/b.bin", "has\0a\0nul")
  local bindir_srcs = scope.resolve("path", { path = bindir })
  eq(#bindir_srcs, 1, "scope.resolve(path, dir): binary sibling is skipped, not raised")
  eq(
    bindir_srcs[1].file:match("a%.txt$") ~= nil,
    true,
    "scope.resolve(path, dir): the text file is the one kept"
  )

  -- max_filesize: a file larger than the limit is skipped like a binary one.
  local bigdir = dir .. "/bigdir"
  vim.fn.mkdir(bigdir, "p")
  write_raw(bigdir .. "/small.txt", "tiny")
  write_raw(bigdir .. "/big.txt", string.rep("x", 100))
  local sized = scope.resolve("path", { path = bigdir, max_filesize = 10 })
  eq(#sized, 1, "scope.resolve: oversized file excluded by max_filesize")
  eq(
    sized[1].file:match("small%.txt$") ~= nil,
    true,
    "scope.resolve: the small file survives max_filesize"
  )

  -- Single-file max_filesize: same limit applied to a direct (non-dir) path.
  local _, big_single_err =
    scope.resolve("path", { path = bigdir .. "/big.txt", max_filesize = 10 })
  ok(
    big_single_err ~= nil,
    "scope.resolve(path): oversized single file reports an error, not silently truncated"
  )

  -- max_files: cap the number of files returned even when more exist; paths
  -- are sorted first, so the cap is deterministic (alphabetically first N).
  local manydir = dir .. "/manydir"
  vim.fn.mkdir(manydir, "p")
  for i = 1, 5 do
    write_raw(("%s/f%d.txt"):format(manydir, i), "x")
  end
  local capped = scope.resolve("path", { path = manydir, max_files = 2 })
  eq(#capped, 2, "scope.resolve: max_files caps the result count")

  -- range: clamped to the buffer's real bounds, and `first` reports the
  -- true starting line so partial-scope hits don't misreport as line 1.
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "l1", "l2", "l3", "l4", "l5" })

  local mid = scope.resolve("range", { bufnr = bufnr, line1 = 2, line2 = 4 })
  eq(#mid[1].lines, 3, "scope.resolve(range): line1..line2 inclusive")
  eq(mid[1].first, 2, "scope.resolve(range): first reports the real starting line")
  eq(mid[1].lines[1], "l2", "scope.resolve(range): first line matches line1")

  local clamped = scope.resolve("range", { bufnr = bufnr, line1 = -5, line2 = 999 })
  eq(#clamped[1].lines, 5, "scope.resolve(range): line1/line2 clamp to the buffer's real bounds")
  eq(clamped[1].first, 1, "scope.resolve(range): line1 below 1 clamps to 1")

  local _, empty_err = scope.resolve("range", { bufnr = bufnr, line1 = 4, line2 = 2 })
  ok(empty_err ~= nil, "scope.resolve(range): line2 < line1 reports an error")

  vim.api.nvim_buf_delete(bufnr, { force = true })

  -- unknown scope kind reports an error rather than silently returning {}.
  local _, unk_err = scope.resolve("not-a-real-kind")
  ok(unk_err ~= nil, "scope.resolve: unknown kind reports an error")

  -- resolve_token: free-form dispatch.
  local by_path = scope.resolve_token(plain)
  eq(#by_path, 1, "resolve_token: a bare path token resolves as a path scope")
  local by_empty = scope.resolve_token("")
  eq(#by_empty, 1, "resolve_token: empty token falls back to the current buffer")

  -- ------------------------------------------------------------ render.*

  -- Pipe escaping: an unescaped "|" would silently split a cell in the GFM
  -- output, so it must come back escaped.
  local gfm = render.markdown_table({ "A", "B" }, { { "a|b", "plain" } })
  ok(gfm:find("a\\|b", 1, true) ~= nil, "render.markdown_table: a literal | is escaped")

  -- Column alignment measured in display width, not byte length: "café" is
  -- 5 bytes (é is 2 UTF-8 bytes) but only 4 display cells, one narrower
  -- than "abcde" (5 bytes AND 5 display cells). If padding used byte
  -- length, both would already "fit" the width-5 column with zero padding
  -- added and café would render visually short by one cell.
  local wide = render.markdown_table({ "Name" }, { { "café" }, { "abcde" } })
  local wide_lines = vim.split(wide, "\n", { plain = true })
  ok(
    wide_lines[3]:match("  |$") ~= nil,
    "render.markdown_table: café (display width 4) gets a padding space to reach column width 5"
  )
  ok(
    wide_lines[4]:match("[^ ] |$") ~= nil,
    "render.markdown_table: abcde (display width 5 already) needs no extra padding"
  )

  -- A newline embedded in a cell is flattened to a space, never a raw
  -- newline (which would add a spurious extra table line and corrupt the
  -- row structure).
  local flattened = render.markdown_table({ "X" }, { { "a\nb" } })
  local flat_lines = vim.split(flattened, "\n", { plain = true })
  eq(#flat_lines, 3, "render.markdown_table: an embedded newline does not add an extra table line")
  ok(
    flat_lines[3]:find("a b", 1, true) ~= nil,
    "render.markdown_table: an embedded newline is flattened to a space"
  )

  -- CSV: RFC 4180 quoting for a field containing the separator, a quote, or
  -- a newline; an embedded quote is doubled.
  local csv = render.csv({ "a", "b" }, { { "has,comma", 'has"quote' } })
  local csv_lines = vim.split(csv, "\n", { plain = true })
  ok(
    csv_lines[2]:find('"has,comma"', 1, true) ~= nil,
    "render.csv: a comma-containing field is quoted"
  )
  ok(
    csv_lines[2]:find('"has""quote"', 1, true) ~= nil,
    "render.csv: an embedded quote is doubled and the field is quoted"
  )

  local plain_csv = render.csv(nil, { { "x", "y" } })
  eq(plain_csv, "x,y", "render.csv: nil headers omits the header row")

  -- lines: cells joined with the separator, rows joined with newlines.
  eq(render.lines({ { "x", "y" } }, " - "), "x - y", "render.lines: custom separator between cells")
  eq(
    render.lines({ { "a" }, { "b" } }),
    "a\nb",
    "render.lines: rows joined by newline, default cell separator"
  )

  -- ------------------------------------------------------------- emit/outputs

  eq(harvest.emit("", "table"), false, "emit: empty text reports 'nothing to emit'")

  local out_path = dir .. "/emit_out.md"
  local ok_write = harvest.emit("hello", "file:" .. out_path)
  eq(ok_write, true, "emit: file:<path> token writes via sink.file")
  local f = assert(io.open(out_path, "r"))
  eq(f:read("*a"), "hello\n", "emit: file sink wrote the expected content")
  f:close()

  local ok_unknown, unknown_err = harvest.emit("x", "not-a-real-sink")
  eq(ok_unknown, false, "emit: unrecognized output token fails")
  ok(unknown_err ~= nil, "emit: unrecognized output token reports an error")

  local outs = harvest.outputs()
  local set = {}
  for _, o in ipairs(outs) do
    set[o] = true
  end
  for _, want in ipairs({ "buffer", "clipboard", "echo", "file:", "table" }) do
    ok(set[want] == true, "outputs(): includes " .. want)
  end
end
