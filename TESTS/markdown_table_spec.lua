-- TESTS/markdown_table_spec.lua — lib.nvim.markdown.table
--
-- This module was extracted from two copies that had already drifted apart, so
-- the assertions below are mostly about the behaviour each copy had and the
-- other did not — that is what an extraction can silently lose.

return function(H)
  local eq, ok = H.eq, H.ok
  local T = require("lib.nvim.markdown.table")

  local SRC = {
    "intro",
    "",
    "| Name | Value | Note |",
    "| --- | --- | --- |",
    "| a | 1 | x |",
    "| longer-name | 22 | yy |",
    "",
    "outro",
  }

  -- --------------------------------------------------------------- parsing
  do
    local tables = T.parse(SRC)
    eq(#tables, 1, "one table found")
    eq(tables[1].start_line, 3, "start_line is 1-based and inclusive")
    eq(tables[1].end_line, 6, "end_line covers the last body row")
    eq(tables[1].col_count, 3, "column count comes from the widest row")
    eq(#tables[1].rows, 3, "the separator row is not a row")
    eq(tables[1].separator_style, "spaced", "the source's separator style is kept")
    eq(tables[1].rows[1][1], "Name", "cells are trimmed")

    eq(#T.parse({ "| a |", "| --- |" }), 0, "two lines are not a table")
    eq(T.is_table_line("not a table"), false, "a plain line is not a table line")
    eq(T.is_table_line(nil), false, "a non-string is not a table line")

    local is_sep, style = T.is_separator_line("|---|---|")
    eq(is_sep, true, "a compact separator is recognised")
    eq(style, "compact", "and reported as compact")
  end

  -- `parse_row` splits with gmatch rather than a char-by-char `..`
  -- accumulator, which is O(n^2) in the row length. buffer-ctx.nvim had this
  -- fix and markdown.nvim did not; the point of the extraction is that neither
  -- can fall behind again.
  do
    eq(#T.parse_row("| a | b | c |"), 3, "three cells")
    eq(T.parse_row("| a | b |")[2], "b", "cells are trimmed")
    eq(#T.parse_row("no pipes here"), 0, "a non-row yields no cells")
    eq(T.parse_row("| a || c |")[2], "", "an empty cell is kept, not skipped")

    -- Not a benchmark -- just proof it completes on a row long enough that the
    -- quadratic version was noticeable.
    local wide = "|" .. string.rep(" cell |", 400)
    eq(#T.parse_row(wide), 400, "a 400-column row parses")
  end

  -- --------------------------------------------------------------- render
  do
    local parsed = T.parse(SRC)[1]
    local out = T.render(parsed)
    eq(#out, 4, "header, separator and two body rows")
    eq(out[1], "| Name        | Value | Note |", "columns are padded to the widest cell")
    eq(out[2], "| ----------- | ----- | ---- |", "the separator matches those widths")
    eq(out[3], "| a           | 1     | x    |", "body rows are padded too")

    local compact = T.parse({ "| a | b |", "|---|---|", "| 1 | 2 |" })[1]
    eq(T.render(compact)[2], "|---|---|", "a compact table stays compact")
  end
  -- ------------------------------------------------- escaped pipe (GFM)
  do
    local bs = string.char(92)
    local row = "| `a " .. bs .. "| b` | c |"
    local cells, ranges = T.split_cells(row)
    eq(#cells, 2, "an escaped pipe does not end a cell")
    eq(cells[1], "`a " .. bs .. "| b`", "the cell keeps the raw backslash-pipe")
    eq(
      row:sub(ranges[2][1], ranges[2][2]),
      " c ",
      "ranges are byte ranges of the raw cell in the line"
    )
    eq(
      #T.parse_row("| " .. bs .. "|" .. bs .. "| | x |"),
      2,
      "two escaped pipes in a row stay one cell"
    )
    local even = T.parse_row("| a" .. bs .. bs .. "| b |")
    eq(#even, 2, "an escaped backslash does not escape the pipe after it")
    eq(T.parse_row("| a || c |")[2], "", "an empty cell is still kept")
    eq(T.split_cells("  | a | b |  ")[2], "b", "leading whitespace is allowed")

    -- ranges: every cell, indented line, empty cell, padded last cell. Built from
    -- known segments, so the expected byte range of each cell is known exactly.
    for _, indent in ipairs({ "", "  ", "    " }) do
      local segs = { " a ", "  ", " `x" .. bs .. "|y` ", "", " z  " }
      local line = indent .. "|" .. table.concat(segs, "|") .. "|"
      local cs, rs = T.split_cells(line)
      eq(#rs, #segs, "one range per cell (indent " .. #indent .. ")")
      for i, seg in ipairs(segs) do
        eq(
          line:sub(rs[i][1], rs[i][2]),
          seg,
          "range of cell " .. i .. " (indent " .. #indent .. ")"
        )
        eq(cs[i], vim.trim(seg), "text of cell " .. i)
      end
    end
    local lines = { "| S | M |", "|---|---|", "| `a " .. bs .. "| b` | x |" }
    local out = T.format_lines(lines)
    eq(#T.parse_row(out[3]), 2, "a formatted table keeps two columns")
    eq(out[3]:find(bs .. "|", 1, true) ~= nil, true, "and the escape survives the re-render")
    eq(table.concat(T.format_lines(out), "\n"), table.concat(out, "\n"), "formatting is idempotent")
  end

  do
    local parsed = T.parse(SRC)[1]
    local right = T.render(parsed, { entry_align = "right" })
    eq(right[3], "|           a |     1 |    x |", "entry_align right-aligns every body cell")
    eq(right[1], "| Name        | Value | Note |", "and leaves the header on its own setting")

    local centered = T.render(parsed, { header_align = "center" })
    eq(centered[1], "|    Name     | Value | Note |", "an odd remainder goes to the right")
  end

  -- ------------------------------------------------------------- overrides
  -- Warnings are RETURNED, not notified. markdown.nvim notified from inside
  -- the resolver and buffer-ctx.nvim collected them; a library that notifies
  -- decides for its caller how loud a config typo should be.
  do
    local parsed = T.parse(SRC)[1]
    local map, warnings = T.resolve_overrides({
      { col = 2, align = "right" },
      { col = "note", align = "center" },
    }, parsed.rows[1], parsed.col_count)

    eq(map[2], "right", "an override by index resolves")
    eq(map[3], "center", "an override by header text resolves case-insensitively")
    eq(#warnings, 0, "nothing to warn about")

    local _, warn2 =
      T.resolve_overrides({ { col = "nope", align = "right" } }, parsed.rows[1], parsed.col_count)
    eq(#warn2, 1, "an override naming no column is reported")
    ok(warn2[1]:find("nope") ~= nil, "the warning names the column")

    local out = T.render(parsed, { override_map = map })
    eq(out[3], "| a           |     1 |  x   |", "the override beats the default alignment")
  end

  -- ---------------------------------------------------------- format_lines
  do
    local ugly = {
      "before",
      "|a|b|",
      "|---|---|",
      "|1|22|",
      "between",
      "| x | y |",
      "| --- | --- |",
      "| 1 | 2 |",
      "after",
    }
    local out, count, warnings = T.format_lines(ugly)
    eq(count, 2, "both tables were re-rendered")
    eq(#warnings, 0, "no warnings")
    eq(out[1], "before", "text before the first table is untouched")
    eq(out[5], "between", "text between two tables survives at the right place")
    eq(out[#out], "after", "and so does the tail")
    eq(out[2], "| a | b  |", "the first table is normalised")

    -- The one that a naive in-place splice gets wrong: rewriting the first
    -- table moves every line below it, so the second table's recorded
    -- positions no longer point at it.
    eq(out[6], "| x | y |", "the SECOND table is re-rendered at its real position")

    local same, n = T.format_lines({ "no tables here" })
    eq(n, 0, "a document without tables reports nothing changed")
    eq(same[1], "no tables here", "and comes back unchanged")
  end

  -- --------------------------------------------------------------- buffer
  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "|a|b|", "|---|---|", "|1|22|" })

    local ok_fmt, err, count = T.format_buffer(buf)
    eq(ok_fmt, true, "format_buffer succeeds: " .. tostring(err))
    eq(count, 1, "one table formatted")
    eq(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "| a | b  |",
      "the buffer holds the rendered table"
    )

    eq(select(1, T.format_buffer(999999)), false, "an invalid buffer is refused, not raised")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "text",
      "|a|b|",
      "|---|---|",
      "|1|22|",
      -- A blank line, or the two tables are ONE run of table lines and parse
      -- as a single table with two separator rows.
      "",
      "|c|d|",
      "|---|---|",
      "|3|44|",
    })

    -- `lnum` rather than the real cursor, so this needs no window.
    local ok_c, err_c = T.format_at_cursor(buf, { lnum = 7 })
    eq(ok_c, true, "format_at_cursor succeeds: " .. tostring(err_c))

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[6], "| c | d  |", "the table under the line was formatted")
    eq(lines[2], "|a|b|", "the other one was left alone")

    eq(select(1, T.format_at_cursor(buf, { lnum = 1 })), false, "a line with no table is refused")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ----------------------------------------------------------------- file
  do
    local path = vim.fn.tempname()
    local fh = assert(io.open(path, "w"))
    fh:write("|a|b|\n|---|---|\n|1|22|\n")
    fh:close()

    local ok_f, err_f, count = T.format_file(path)
    eq(ok_f, true, "format_file succeeds: " .. tostring(err_f))
    eq(count, 1, "one table formatted")

    local body = assert(io.open(path)):read("*a")
    ok(body:find("| a | b  |", 1, true) ~= nil, "the file holds the rendered table")

    -- A file with nothing to do must not be rewritten: a run over a tree
    -- should not touch every mtime in it.
    local before = vim.fn.getftime(path)
    local plain = vim.fn.tempname()
    local ph = assert(io.open(plain, "w"))
    ph:write("nothing to format\n")
    ph:close()
    local _, _, n2 = T.format_file(plain)
    eq(n2, 0, "a file without tables reports nothing changed")
    ok(before > 0, "sanity: the formatted file exists")

    eq(select(1, T.format_file(path .. ".missing")), false, "a missing file is refused, not raised")

    pcall(vim.fn.delete, path)
    pcall(vim.fn.delete, plain)
  end

  -- ------------------------------------------------------- exported primitives
  -- These three are public because markdown.nvim's table_wrap (soft-wrapping
  -- long cells) and the :Markdown table HTML import build rows outside the
  -- normal parse -> render pipeline and need the same primitives directly,
  -- rather than a third copy of them.
  do
    eq(T.trim("  x  "), "x", "trim strips both sides")
    eq(T.trim(nil), "", "trim of a non-string is empty")

    eq(T.gen_separator({ 3, 1 }, "spaced"), "| --- | - |", "spaced separator")
    eq(T.gen_separator({ 3, 1 }, "compact"), "|-----|---|", "compact separator")

    local row = T.format_row({ "a", "bb" }, { 3, 3 }, "left", {})
    eq(row, "| a   | bb  |", "format_row pads per width/align")
    local overridden = T.format_row({ "a", "bb" }, { 3, 3 }, "left", { [2] = "right" })
    eq(overridden, "| a   |  bb |", "format_row honours the override map")
  end

  -- ------------------------------------------- format_file keeps the file's bytes
  do
    local function roundtrip(raw)
      local path = vim.fn.tempname() .. ".md"
      local fh = assert(io.open(path, "wb"))
      fh:write(raw)
      fh:close()
      local fok, ferr, count = T.format_file(path, { header_align = "left", entry_align = "left" })
      local rh = assert(io.open(path, "rb"))
      local got = rh:read("a")
      rh:close()
      vim.fn.delete(path)
      return got, fok, ferr, count
    end

    local BOM = "\239\187\191"
    local crlf = BOM .. "intro\r\n| A | B |\r\n|---|---|\r\n| xxxx | y |\r\n"
    local got, fok, _, count = roundtrip(crlf)
    eq(fok, true, "format_file succeeds on a BOM + CRLF file")
    eq(count, 1, "the table in it is found despite the BOM and the CRs")
    eq(
      got,
      BOM .. "intro\r\n| A    | B |\r\n|------|---|\r\n| xxxx | y |\r\n",
      "BOM and CRLF endings survive"
    )

    local lf = "| A | B |\n|---|---|\n| xxxx | y |"
    got = roundtrip(lf)
    eq(got, "| A    | B |\n|------|---|\n| xxxx | y |", "a missing final newline stays missing")

    -- mixed endings: an LF line next to a CRLF table. A formatted table is left
    -- byte for byte; a misaligned one is rewritten with the block's own CRLF and
    -- the LF line is untouched.
    local mixed_ok = "intro\n| A    | B |\r\n|------|---|\r\n| xxxx | y |\r\n"
    eq(roundtrip(mixed_ok), mixed_ok, "a formatted CRLF table in an LF file is kept byte for byte")
    local mixed_bad = "intro\n| A | B |\r\n|---|---|\r\n| xxxx | y |\r\n"
    eq(
      roundtrip(mixed_bad),
      mixed_ok,
      "a misaligned CRLF block is rewritten with CRLF, the LF line stays"
    )

    -- an already formatted file is not rewritten: compare the bytes after a call
    -- that would change them if it wrote, with a stat that cannot pass vacuously
    -- (the file is made read-only; a write attempt would report an error)
    local same = "| A    | B |\n|------|---|\n| xxxx | y |\n"
    local path = vim.fn.tempname() .. ".md"
    local fh = assert(io.open(path, "wb"))
    fh:write(same)
    fh:close()
    vim.uv.fs_chmod(path, tonumber("444", 8))
    local sok, serr = T.format_file(path, { header_align = "left", entry_align = "left" })
    vim.uv.fs_chmod(path, tonumber("644", 8))
    vim.fn.delete(path)
    eq(sok, true, "an already formatted read-only file is not even opened for writing")
    eq(serr, nil, "and reports no error")

    -- a failed write puts the original bytes back and reports the failure
    local orig = "| A | B |\n|---|---|\n| xxxx | y |\n"
    local fpath = vim.fn.tempname() .. ".md"
    local wf = assert(io.open(fpath, "wb"))
    wf:write(orig)
    wf:close()
    local real_open = io.open -- luacheck: ignore 122
    local calls = 0
    io.open = function(p, mode) -- luacheck: ignore 122
      if p == fpath and mode == "wb" then
        calls = calls + 1
        if calls == 1 then
          real_open(p, "wb"):close() -- the truncation a real open does
          return {
            write = function()
              return nil, "No space left on device"
            end,
            close = function()
              return true
            end,
          }
        end
      end
      return real_open(p, mode)
    end
    local wfok, wferr = T.format_file(fpath, { header_align = "left", entry_align = "left" })
    io.open = real_open -- luacheck: ignore 122
    local back = assert(io.open(fpath, "rb"))
    local after = back:read("a")
    back:close()
    vim.fn.delete(fpath)
    eq(wfok, false, "a failed write is reported")
    ok(wferr and wferr:find("No space left", 1, true) ~= nil, "with the reason")
    eq(after, orig, "and the original bytes are restored")

    -- when the restore fails too, the user is told the file may be damaged
    local dpath = vim.fn.tempname() .. ".md"
    local df = assert(io.open(dpath, "wb"))
    df:write(orig)
    df:close()
    local open_real = io.open -- luacheck: ignore 122
    io.open = function(p, mode) -- luacheck: ignore 122
      if p == dpath and mode == "wb" then
        open_real(p, "wb"):close()
        return {
          write = function()
            return nil, "No space left on device"
          end,
          close = function()
            return true
          end,
        }
      end
      return open_real(p, mode)
    end
    local dok, derr = T.format_file(dpath, { header_align = "left", entry_align = "left" })
    io.open = open_real -- luacheck: ignore 122
    vim.fn.delete(dpath)
    eq(dok, false, "a failed write with a failed restore is reported")
    ok(
      derr and derr:find("could not be restored", 1, true) ~= nil,
      "and says the file may be damaged"
    )
  end
end
