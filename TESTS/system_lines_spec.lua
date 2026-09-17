-- TESTS/system_lines_spec.lua -- lib.nvim.system.lines
--
-- The two things only real streaming exposes: a line split across chunk
-- boundaries, and the trailing CR that `vim.system`'s `text = true` does not
-- strip for a function handler. Both used to be re-implemented per consumer,
-- and each copy got one of them wrong at some point.

return function(H)
  local eq, ok = H.eq, H.ok
  local lines = require("lib.nvim.system.lines")

  -- collector: chunk boundaries ------------------------------------------
  do
    local c = lines.collector()
    eq(#c.feed("par"), 0, "collector: an incomplete line is held back")
    eq(table.concat(c.feed("tial\n"), "|"), "partial", "collector: the split line is rejoined")
    eq(c.flush(), nil, "collector: flush with nothing buffered returns nil")
  end

  do
    local c = lines.collector()
    eq(table.concat(c.feed("one\ntwo\nthr"), "|"), "one|two", "collector: whole lines only")
    eq(c.flush(), "thr", "collector: flush hands back the trailing partial")
  end

  do
    -- Output that never ends in a newline still has a last line.
    local c = lines.collector()
    eq(#c.feed("no trailing newline"), 0, "collector: unterminated output waits")
    eq(c.flush(), "no trailing newline", "collector: flush emits it")
    eq(c.flush(), nil, "collector: a second flush has nothing left")
  end

  -- collector: CR handling ------------------------------------------------
  do
    local c = lines.collector()
    eq(table.concat(c.feed("one\r\ntwo\r\n"), "|"), "one|two", "collector: CRLF is stripped")
  end

  do
    -- The case that defeats normalizing each chunk on its own: the pair is
    -- torn in half, so neither chunk contains it.
    local c = lines.collector()
    eq(#c.feed("value\r"), 0, "collector: a chunk ending in CR is held back")
    eq(table.concat(c.feed("\nrest"), "|"), "value", "collector: a torn CRLF still strips")
    eq(c.flush(), "rest", "collector: and the rest survives")
  end

  do
    -- A remainder of exactly one CR is a line ending whose newline never
    -- arrived, not a line. It used to come back as "" -- truthy in Lua -- so
    -- a caller writing `if last then ...` put a blank line at the end of
    -- every such stream.
    local c = lines.collector()
    eq(#c.feed("done\r\ntail\r"), 1, "collector: the complete line comes through")
    eq(c.flush(), "tail", "collector: the partial keeps its content")

    local only_cr = lines.collector()
    only_cr.feed("\r")
    eq(only_cr.flush(), nil, "collector: a remainder of just a CR is nothing, not an empty line")
  end

  do
    -- ...while a genuinely blank final line still arrives, via feed.
    local c = lines.collector()
    local got = c.feed("a\n\n")
    eq(#got, 2, "collector: a blank line before EOF is a line")
    eq(got[2], "", "collector: ...and it is empty")
    eq(c.flush(), nil, "collector: nothing is left over after it")
  end

  do
    -- A CR inside a line is the process's own output.
    local c = lines.collector()
    eq(table.concat(c.feed("mid\rdle\n"), "|"), "mid\rdle", "collector: interior CR is kept")
  end

  do
    -- Blank lines are the caller's business, so they come through.
    local c = lines.collector()
    local got = c.feed("\n\nx\n")
    eq(#got, 3, "collector: blank lines are reported, not dropped")
    eq(got[3], "x", "collector: ...in order")
  end

  do
    -- Two streams must not complete each other's lines.
    local out, err = lines.collector(), lines.collector()
    eq(#out.feed("foo"), 0, "collector: stdout partial waits")
    eq(table.concat(err.feed("bar\n"), "|"), "bar", "collector: stderr completes on its own")
    eq(table.concat(out.feed("\n"), "|"), "foo", "collector: stdout is completed by stdout")
  end

  -- buffered: the vim.system handler shape --------------------------------
  eq(lines.buffered(nil), nil, "buffered: a nil callback yields no handler")

  do
    local got = {}
    local handler = lines.buffered(function(_, line)
      got[#got + 1] = line
    end)
    ok(type(handler) == "function", "buffered: returns a handler")

    handler(nil, "alpha\r\nbet")
    handler(nil, "a\n")
    handler(nil, nil) -- EOF
    vim.wait(200, function()
      return #got >= 2
    end, 10)
    eq(table.concat(got, "|"), "alpha|beta", "buffered: lines arrive whole, CR stripped")
  end

  do
    -- EOF flushes output that never got its newline.
    local got = {}
    local handler = lines.buffered(function(_, line)
      got[#got + 1] = line
    end)
    handler(nil, "last line, no newline")
    handler(nil, nil)
    vim.wait(200, function()
      return #got >= 1
    end, 10)
    eq(table.concat(got, "|"), "last line, no newline", "buffered: EOF flushes the tail")
  end
end
