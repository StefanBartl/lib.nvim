---@meta
---@module 'lib.nvim.harvest.@types'

--- One contiguous chunk of text to scan, tagged with where it came from so a
--- caller can map a hit back to a file/buffer position.
---@class Lib.Harvest.Source
---@field file string|nil    Absolute path, when the content came from disk or a named buffer.
---@field bufnr integer|nil  Buffer the content came from, when it came from a buffer.
---@field lines string[]     The raw lines.
---@field first integer      1-based line number of `lines[1]` in its file/buffer.

---@alias Lib.Harvest.ScopeKind
---| "buffer"   # the current (or `opts.bufnr`) buffer
---| "buffers"  # every listed, loaded buffer
---| "range"    # a line range of one buffer (`opts.line1`/`opts.line2`)
---| "cwd"      # every matching file under `vim.fn.getcwd()`
---| "path"     # a single file, or every matching file under a directory

---@class Lib.Harvest.ScopeOpts
---@field bufnr integer|nil       Buffer for "buffer"/"range". Defaults to the current buffer.
---@field line1 integer|nil       1-based inclusive start line for "range".
---@field line2 integer|nil       1-based inclusive end line for "range".
---@field path string|nil         File or directory for "path". Required for that kind.
---@field recursive boolean|nil   Descend into subdirectories. Defaults to true; pass false for a shallow scan.
---@field match string|nil        Lua pattern a file's basename must match to be read (e.g. "%.md$").
---@field ignore (fun(abs: string, is_dir: boolean): boolean)|nil  Prune predicate; defaults to lib.nvim's shared ignore list.
---@field max_files integer|nil   Stop after reading this many files. Defaults to 2000.
---@field max_filesize integer|nil Skip files larger than this many bytes. Defaults to 1 MiB.

---@class Lib.Harvest.TableOpts
---@field align ("l"|"c"|"r")[]|nil  Per-column alignment; defaults to all-left.

---@class Lib.Harvest.ScratchOpts
---@field title string|nil     Buffer name.
---@field filetype string|nil  Filetype to set. Defaults to "markdown".
---@field split string|nil     "split" | "vsplit" | "tab" | "current". Defaults to "split".

---@class Lib.Harvest.SelectOpts
---@field prompt string|nil
---@field format (fun(item: any): string)|nil

--- `lib.nvim.harvest.scope` module surface.
---@class Lib.Harvest.Scope
---@field resolve fun(kind: Lib.Harvest.ScopeKind|string|nil, opts: Lib.Harvest.ScopeOpts|nil): Lib.Harvest.Source[], string|nil
---@field resolve_token fun(token: string|nil, opts: Lib.Harvest.ScopeOpts|nil): Lib.Harvest.Source[], string|nil

--- `lib.nvim.harvest.render` module surface.
---@class Lib.Harvest.Render
---@field markdown_table fun(headers: string[], rows: any[][], opts: Lib.Harvest.TableOpts|nil): string
---@field csv fun(headers: string[]|nil, rows: any[][], sep: string|nil): string
---@field lines fun(rows: any[][], sep: string|nil): string

--- `lib.nvim.harvest.sink` module surface.
---@class Lib.Harvest.Sink
---@field clipboard fun(text: string): boolean, string|nil
---@field file fun(text: string, path: string): boolean, string|nil
---@field scratch fun(text: string, opts: Lib.Harvest.ScratchOpts|nil): integer
---@field select fun(items: any[], opts: Lib.Harvest.SelectOpts|nil, on_choose: fun(item: any, idx: integer))

--- `lib.nvim.harvest` module surface.
---@class Lib.Harvest
---@field scope Lib.Harvest.Scope
---@field render Lib.Harvest.Render
---@field sink Lib.Harvest.Sink
---@field emit fun(text: string, out: string|nil, opts: (Lib.Harvest.ScratchOpts|{ path?: string })|nil): boolean, string|nil
---@field outputs fun(): string[]

return {}
