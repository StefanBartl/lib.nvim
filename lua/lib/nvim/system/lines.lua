---@module 'lib.nvim.system.lines'
--- Turning a subprocess's output chunks into whole lines.
---
--- Nothing that reads a process hands over lines. `vim.system`'s `stdout` /
--- `stderr` function handlers pass whatever libuv read, so a chunk can end
--- mid-line and the rest arrive in the next one. `jobstart` has the same
--- property in list form (`:h channel-lines`): the first element of a callback
--- continues the last element of the previous one. Code that splits each chunk
--- on its own therefore cuts those lines in two -- measured on 4000 lines of
--- output: 4026 entries, 26 of them malformed.
---
--- The trailing CR goes too, and that is not optional either. `vim.system`'s
--- `text = true` normalizes CRLF only for the stdout it captures *itself* --
--- it does not cover a function handler, so passing it alongside one reads
--- like a guarantee that never applied. On Windows every line would otherwise
--- carry a CR.
---
--- The trailing partial is held in memory until its newline arrives, with no
--- bound: output that never emits one accumulates in full. That is inherent to
--- line buffering rather than a choice made here, but it is worth knowing
--- before streaming something whose shape you do not control -- a caller that
--- needs a ceiling has to impose it on the process, not on this.
---
--- Both shapes are here because callers genuinely need both: `M.collector()`
--- when you want to pull lines out of chunks you already have, `M.buffered()`
--- when you want a ready-made `vim.system` handler that calls you per line.
--- The second is built on the first.
---
--- >lua
---   local lines = require("lib.nvim.system.lines")
---
---   -- pull: hand it chunks, get whole lines back
---   local c = lines.collector()
---   for _, line in ipairs(c.feed(chunk)) do ... end
---   local last = c.flush()   -- output that never got its newline
---
---   -- push: a vim.system stdout/stderr handler
---   vim.system(cmd, { stdout = lines.buffered(function(_, line) ... end) })
--- <

require("lib.nvim.system.@types")

local M = {}

---@internal
---Strip the one trailing CR a CRLF line ending leaves behind. A CR *inside*
---the line is the process's own output and stays.
---@param line string
---@return string
local function strip_cr(line)
  if line:sub(-1) == "\r" then
    return line:sub(1, -2)
  end
  return line
end

---A line collector: feed it output chunks, get whole lines back.
---
---The trailing partial is held back until more of the same stream completes
---it, so give each stream its own collector. A shared one would let a stdout
---chunk that has not seen its newline yet be completed by whatever stderr
---delivers first, producing a line that existed in neither.
---
---Blank lines are returned as `""` rather than dropped: whether an empty line
---means anything is the caller's question, not this module's.
---@return Lib.System.Lines.Collector
function M.collector()
  local buffered = ""

  return {
    feed = function(data)
      buffered = buffered .. data
      local parts = vim.split(buffered, "\n", { plain = true })
      -- The last part is either a partial line or "" (the chunk ended on a
      -- newline). Either way it is not complete, so it stays buffered -- which
      -- is also why a CRLF torn across two chunks still works: the pair is
      -- only ever examined once both halves are in `buffered`.
      buffered = table.remove(parts) or ""
      for i = 1, #parts do
        parts[i] = strip_cr(parts[i])
      end
      return parts
    end,

    flush = function()
      -- Strip before deciding, not after: a remainder of exactly "\r" is a
      -- line ending whose newline never arrived, not a line. Testing
      -- emptiness first returned it as "", which is truthy in Lua, so a
      -- caller writing `if last then ...` emitted a blank line at the end of
      -- every such stream.
      local last = strip_cr(buffered)
      buffered = ""
      if last == "" then
        return nil
      end
      return last
    end,
  }
end

---A `vim.system` `stdout`/`stderr` handler that calls `cb` once per whole
---line, on the main loop.
---
---Returns nil for a nil `cb`, so it can wrap an optional handler without the
---caller branching. The `err` argument libuv reports is not forwarded: this
---exists to deliver lines, and every caller so far treats a read error as the
---process failing, which the exit callback already reports.
---@param cb fun(err: nil, line: string)|nil
---@return fun(err: string|nil, data: string|nil)|nil
function M.buffered(cb)
  if not cb then
    return nil
  end

  local collector = M.collector()

  return function(_, data)
    if not data then
      -- EOF. A trailing fragment with no newline after it is still a line, and
      -- plenty of real output ends that way -- a file whose last line has no
      -- terminator, `printf` without a trailing \n, a program killed mid-line.
      -- Returning here without flushing drops it silently.
      local last = collector.flush()
      if last then
        vim.schedule(function()
          cb(nil, last)
        end)
      end
      return
    end

    for _, line in ipairs(collector.feed(data)) do
      vim.schedule(function()
        cb(nil, line)
      end)
    end
  end
end

return M
