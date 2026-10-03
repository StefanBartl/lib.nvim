---@meta
---@module 'lib.nvim.markdown.frontmatter.@types'

--- A frontmatter value: a string, a boolean, a number (only when parsed with
--- `numbers = true`, or when a patch wrote one and `numbers` is on), or a
--- list of strings (`[a, b]`).
---@alias Lib.Markdown.Frontmatter.Value string|boolean|number|string[]

--- One line of the block between the delimiters, as read.
---@class Lib.Markdown.Frontmatter.Entry
---@field raw string                      # The line without its line ending, exactly as written.
---@field eol string                      # `"\n"`, `"\r\n"`, or `""` (only the last line of a file).
---@field line integer                    # 1-based line number in the file (the opening `---` is line 1).
---@field key? string                     # Set on `key: value` lines (also unreadable ones, see `opaque`).
---@field value? Lib.Markdown.Frontmatter.Value
---@field comment? string                 # A trailing `# ...` comment, kept when the line is rewritten.
---@field opaque? string                  # Why the value is not understood; such a line is never rewritten.

--- The result of `parse`. Treat it as read-only except through `patch`/`set`.
---@class Lib.Markdown.Frontmatter.Parsed
---@field has_block boolean               # A closed `---` ... `---` block was found.
---@field unterminated boolean            # The text starts with `---` but no closing line follows.
---@field bom string                      # `"\239\187\191"` when the text starts with a BOM, else `""`.
---@field eol string                      # The block's line ending (the first line's, default `"\n"`).
---@field meta table<string, Lib.Markdown.Frontmatter.Value>
---@field order string[]                  # Keys of `meta` in file order, each once.
---@field body string                     # Everything after the closing `---` line, untouched.
---@field warnings string[]               # Lines that were kept verbatim without being understood.
---@field raw_lines string[]              # The block's lines (without delimiters and line endings).
---@field opaque table<string, string>    # Keys whose value is not understood -> reason; not in `meta`.
---@field entries Lib.Markdown.Frontmatter.Entry[]  # Per-line records; internal, use the functions.
---@field numbers boolean                 # The `numbers` mode this parse was made with.
---@field by_key table<string, Lib.Markdown.Frontmatter.Entry>  # Internal index (last entry wins).
---@field open? string                    # Opening delimiter line (`has_block` only).
---@field open_eol? string
---@field close? string                   # Closing delimiter line (`has_block` only).
---@field close_eol? string

---@class Lib.Markdown.Frontmatter.ParseOpts
---@field numbers? boolean                # Read number-looking plain values as numbers (default: strings).

---@class Lib.Markdown.Frontmatter.PatchOpts : Lib.Markdown.Frontmatter.ParseOpts
---@field create? boolean                 # Add a block when the text has none (default: fail).

--- A map `{ key = value }` (applied in sorted key order) or a list of
--- `{ key, value }` pairs (applied in the given order). A value is a
--- `Lib.Markdown.Frontmatter.Value` or `frontmatter.REMOVE`.
---@alias Lib.Markdown.Frontmatter.Patch table

---@class Lib.Markdown.Frontmatter
---@field REMOVE userdata                 # Patch value that deletes a key (`vim.NIL`).
---@field parse fun(text: string, opts?: Lib.Markdown.Frontmatter.ParseOpts): Lib.Markdown.Frontmatter.Parsed|nil, string|nil
---@field get fun(parsed: Lib.Markdown.Frontmatter.Parsed, key: string, default?: any): any
---@field patch fun(parsed: Lib.Markdown.Frontmatter.Parsed, patch: Lib.Markdown.Frontmatter.Patch, opts?: Lib.Markdown.Frontmatter.PatchOpts): boolean, string|nil
---@field set fun(parsed: Lib.Markdown.Frontmatter.Parsed, key: string, value: any, opts?: Lib.Markdown.Frontmatter.PatchOpts): boolean, string|nil
---@field serialize fun(parsed: Lib.Markdown.Frontmatter.Parsed): string
---@field update_text fun(text: string, patch: Lib.Markdown.Frontmatter.Patch, opts?: Lib.Markdown.Frontmatter.PatchOpts): string|nil, string|nil
---@field add_block fun(text: string, meta?: Lib.Markdown.Frontmatter.Patch, opts?: Lib.Markdown.Frontmatter.PatchOpts): string|nil, string|nil
---@field read fun(path: string, opts?: Lib.Markdown.Frontmatter.ParseOpts): Lib.Markdown.Frontmatter.Parsed|nil, string|nil
---@field update fun(path: string, patch: Lib.Markdown.Frontmatter.Patch, opts?: Lib.Markdown.Frontmatter.PatchOpts): boolean, string|nil

return {}
