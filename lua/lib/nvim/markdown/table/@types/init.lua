---@meta
---@module 'lib.nvim.markdown.table.@types'

--- One GFM pipe table found in a list of lines.
---
--- `start_line`/`end_line` are 1-based and inclusive, and span the whole run
--- of table lines including the separator row — which is *not* in `rows`,
--- because it is regenerated from the column widths rather than kept.
---@class Lib.Markdown.Table
---@field start_line integer
---@field end_line integer
---@field rows string[][]                        # Header first, then the body rows.
---@field col_count integer                      # Widest row wins; short rows are padded out.
---@field separator_style "spaced"|"compact"     # `| --- |` vs `|---|`, preserved from the source.

--- One column-alignment override.
---
--- `col` names a column either by 1-based index or by its header text
--- (case-insensitive).
---@class Lib.Markdown.Table.ColOverride
---@field col integer|string
---@field align "left"|"center"|"right"

---@class Lib.Markdown.Table.RenderOpts
---@field header_align? "left"|"center"|"right"  # Default "left".
---@field entry_align? "left"|"center"|"right"   # Default "left".
---@field override_map? table<integer, string>   # From `resolve_overrides`.
---@field width_fn? fun(s: string): integer      # Override how a cell is measured.

---@class Lib.Markdown.Table.FormatOpts
---@field header_align? "left"|"center"|"right"
---@field entry_align? "left"|"center"|"right"
---@field col_overrides? Lib.Markdown.Table.ColOverride[]
---@field width_fn? fun(s: string): integer
---@field lnum? integer                          # `format_at_cursor` only; defaults to the cursor line.

---@class Lib.Markdown.Table.Mod
---@field display_width fun(str: any): integer
---@field pad_cell fun(str: string, width: integer, align: string, width_fn?: fun(s: string): integer): string
---@field is_table_line fun(line: any): boolean
---@field is_separator_line fun(line: any): boolean, ("spaced"|"compact"|nil)
---@field parse_row fun(line: string): string[]
---@field parse fun(lines: string[]): Lib.Markdown.Table[]
---@field at_cursor fun(tables: Lib.Markdown.Table[], lnum: integer): Lib.Markdown.Table|nil, string|nil
---@field calc_widths fun(rows: string[][], col_count: integer, width_fn?: fun(s: string): integer): integer[]
---@field resolve_overrides fun(overrides: Lib.Markdown.Table.ColOverride[]|nil, header_cells: string[], col_count: integer): table<integer, string>, string[]
---@field render fun(parsed: Lib.Markdown.Table, opts?: Lib.Markdown.Table.RenderOpts): string[]
---@field format_lines fun(lines: string[], opts?: Lib.Markdown.Table.FormatOpts): string[], integer, string[]
---@field format_buffer fun(bufnr: integer|nil, opts?: Lib.Markdown.Table.FormatOpts): boolean, string|nil, integer, string[]
---@field format_at_cursor fun(bufnr: integer|nil, opts?: Lib.Markdown.Table.FormatOpts): boolean, string|nil, string[]
---@field format_file fun(path: string, opts?: Lib.Markdown.Table.FormatOpts): boolean, string|nil, integer, string[]

return {}
