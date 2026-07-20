---@module 'lib.nvim.harvest'
--- Building blocks for "collect something from a scope, then show or export
--- it" features.
---
--- Three independent pieces, usable separately:
---   - `harvest.scope`  — a scope token/kind → `Lib.Harvest.Source[]` (lines + provenance)
---   - `harvest.render` — headers + rows → a GFM table / CSV / plain lines
---   - `harvest.sink`   — text → clipboard / file / scratch buffer / picker
---
--- There is deliberately **no** pipeline object and no plugin registry. The
--- interesting middle step — deciding what counts as a hit — is domain logic,
--- and wrapping a four-line `for` loop in an injected-callback framework buys
--- ceremony rather than reuse. `harvest.emit` below is the one convenience
--- offered, because mapping a user-supplied `out=` token to a sink is the
--- part that would otherwise be copy-pasted verbatim.
---
---```lua
--- local harvest = require("lib.nvim.harvest")
---
--- local sources = harvest.scope.resolve_token("cwd", { match = "%.md$" })
--- local rows = {}
--- for _, src in ipairs(sources) do
---   for i, line in ipairs(src.lines) do
---     if line:match("TODO") then
---       rows[#rows + 1] = { src.file or "[buffer]", src.first + i - 1, line }
---     end
---   end
--- end
--- harvest.emit(harvest.render.markdown_table({ "File", "Line", "Text" }, rows), "table")
---```

require("lib.nvim.harvest.@types")

local M = {}

M.scope = require("lib.nvim.harvest.scope")
M.render = require("lib.nvim.harvest.render")
M.sink = require("lib.nvim.harvest.sink")

--- Send `text` to the sink named by `out`.
---
--- Recognized: `"table"`/`"buffer"` (scratch buffer), `"clipboard"`/`"clip"`,
--- `"echo"`, and `"file:<path>"` (or `"file"` with `opts.path`).
---@param text string
---@param out string|nil  Defaults to "buffer".
---@param opts Lib.Harvest.ScratchOpts|{ path?: string }|nil
---@return boolean ok, string|nil err
function M.emit(text, out, opts)
  opts = opts or {}
  out = out or "buffer"

  if text == "" then
    return false, "nothing to emit"
  end

  local path = opts.path
  -- `file:<path>` keeps the whole sink selection inside one command token,
  -- which is what makes `out=file:/tmp/x.md` work without a second argument.
  local prefix, rest = out:match("^(file):(.+)$")
  if prefix then
    out, path = "file", rest
  end

  if out == "clipboard" or out == "clip" then
    return M.sink.clipboard(text)
  end
  if out == "file" then
    return M.sink.file(text, path)
  end
  if out == "echo" then
    vim.api.nvim_echo({ { text } }, false, {})
    return true, nil
  end
  if out == "table" or out == "buffer" then
    M.sink.scratch(text, opts)
    return true, nil
  end

  return false, ("unknown output '%s'"):format(out)
end

--- The output tokens `emit` understands, for completion.
---@return string[]
function M.outputs()
  return { "buffer", "clipboard", "echo", "file:", "table" }
end

return M
