---@meta
---@module 'lib.nvim.docmap.browse.@types'

---Options for `docmap.browse.open`. `root` is the only required field; the
---rest mirror `Lib.Docmap.Opts` where they overlap so a caller can pass its
---existing docmap opts table straight through.
---@class Lib.Docmap.Browse.Opts
---@field root string Absolute path to the repository root.
---@field source? string Source directory relative to `root`, for the staleness check. Default "lua".
---@field lua_root? string Directory Lua module paths are relative to, used to resolve `center` against namespaces that declare no `@module`. Default "lua".
---@field out_dir? string Where the artifact lives, relative to `root`. Default "docs/map".
---@field live? boolean Install a watching `docmap.install()` handle instead of reading the artifact — costs a full scan up front, but the view then updates on write. Default false.
---@field center? string Node id or `@module` path to open centered on. Default: the map's root.
---@field mode? Lib.Docmap.Browse.Mode Which list to open on. Default "structure".
---@field depth? integer Initial Deps walk depth. Default 2.
---@field theme? Lib.UI.Kit.ThemeArg Passed through to the kit layout.
---@field width? number Fraction of the editor the whole layout uses. Default 0.86.
---@field height? number Default 0.86.
---@field list_width? number Fraction of the layout given to the list column. Default 0.38.

---Which list a browser state is showing.
---@alias Lib.Docmap.Browse.Mode
---| "structure" # Children and functions of the centered node.
---| "deps"      # Require edges, walked to `depth` in `dir`.
---| "calls"     # Call edges touching the centered node/function.
---| "types"     # `@class`/`@alias` declared by the centered node.
---| "history"   # Commits, and the functions each one's diff touches.

---One row of the list. Everything the row can *do* — navigate, open source,
---go into the quickfix list — is a field here rather than something re-derived
---from the rendered text, so the label stays purely presentational.
---@class Lib.Docmap.Browse.Entry
---@field kind "node"|"function"|"type"|"external"|"message"|"commit"
---@field sha string? Full commit hash, for `kind="commit"`.
---@field commit table? The `{ sha, short, author, date, subject }` record behind a `kind="commit"` row.
---@field callers Lib.Docmap.History.Caller[]? Direct callers of a touched function, in History mode — carried on the entry so the detail pane needs no second lookup against an IR that may not describe that revision.
---@field label string Rendered text, including any indent/icon.
---@field id string? Node id this row refers to.
---@field fn string? Declared function name, for `kind="function"`.
---@field type_name string? Type name, for `kind="type"`.
---@field line integer? 1-based line in `source` to jump to.
---@field source string? Repo-relative source path.
---@field site_line integer? `kind="function"` in Calls: line of the call site, which lives in `site_source`, not `source`.
---@field site_source string? Repo-relative path of the file the call site is in.
---@field detail string? One-line hint shown when the row has no richer detail.

---@class Lib.Docmap.Browse
---@field open fun(opts: Lib.Docmap.Browse.Opts): boolean
---@field close fun()
---@field toggle fun(opts: Lib.Docmap.Browse.Opts)
---@field is_open fun(): boolean

return {}
