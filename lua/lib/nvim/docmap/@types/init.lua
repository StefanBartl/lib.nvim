---@meta
---@module 'lib.nvim.docmap.@types'

---Configuration for a docmap run. Every field that could hardcode a
---particular repo's layout is an option, so other plugins can point docmap at
---their own tree.
---@class Lib.Docmap.Opts
---@field root string Absolute path to the repository root.
---@field source? string Directory to scan, relative to `root`. Default "lua".
---@field lua_root? string Directory the Lua module path is relative to. Default "lua".
---@field title? string Display name for the root node. Default: the source directory name.
---@field types_dir? string Directory name holding type definitions, treated as a module attribute. Default "@types".
---@field out_dir? string Output directory, relative to `root`. Default "docs/map".
---@field repo_url? string Base URL used to build source links (e.g. "https://github.com/user/repo").
---@field branch? string Branch used in source links. Default "main".
---@field extra_checks? Lib.Docmap.Check[] Repo-specific drift checks appended to the generic ones.
---@field luals? boolean Merge `lua-language-server --doc` output into the IR (class/alias/field detail, type-reference edges). Off by default — a full-tree run costs real seconds. Default false.
---@field luals_timeout_ms? integer Kill the `lua-language-server --doc` run after this long. Default 60000.
---@field command_name? string Passed to `docmap.command.setup`: register a user command under this name. Default "LibMap".
---@field watch? boolean `install()` only: rescan on `BufWritePost` under `source/**.lua`, debounced. Default false.
---@field watch_ms? integer `install()` only: debounce interval for `watch`. Default 500.

---A repo-specific drift check.
---@alias Lib.Docmap.Check fun(ir: Lib.Docmap.IR, opts: Lib.Docmap.Opts): Lib.Docmap.Finding[]

---@alias Lib.Docmap.Severity "error"|"warn"|"info"

---@alias Lib.Docmap.Kind
---| "module"    # A directory containing init.lua
---| "namespace" # A directory without init.lua, grouping others
---| "file"      # A non-init.lua Lua file

---One node of the map.
---@class Lib.Docmap.Node
---@field id string Stable identifier — the repo-relative path.
---@field kind Lib.Docmap.Kind
---@field name string Display name (directory or file name).
---@field path string Repo-relative path to the directory or file.
---@field source string? Repo-relative path to the Lua source backing this node.
---@field module string? The declared `---@module` path.
---@field summary string One-sentence description, from the header block.
---@field body string Remaining header prose.
---@field readme string? Repo-relative path to a sibling README.md.
---@field types string[] Repo-relative paths of the module's type files.
---@field export ("function"|"table"|"other"|"none")? Export shape of the source file.
---@field parent string? Parent node id.
---@field depth integer Distance from the root node.
---@field children string[] Child node ids, directories first, then files.
---@field types_detail Lib.Docmap.TypeInfo[]? `@class`/`@alias` detail for this node's `types` files, from `lua-language-server --doc`. `nil` when LuaLS enrichment did not run; `{}` is a real "ran, found nothing here" result.
---@field functions Lib.Docmap.FunctionInfo[] Documented functions found in this node's own source file (not its `@types/` files). Always an array, never nil — unlike `types_detail`, this runs unconditionally as part of `scan()`, no LuaLS required.

---A single `@class`/`@alias` parsed from `lua-language-server --doc` output,
---attached to whichever node owns the file it's defined in.
---@class Lib.Docmap.TypeInfo
---@field name string Fully-qualified type name, e.g. "Lib.Docmap.Node".
---@field kind "class"|"alias"
---@field desc string
---@field file string Repo-relative file the type is defined in.
---@field fields Lib.Docmap.TypeField[] Empty for aliases and field-less classes.

---@class Lib.Docmap.TypeField
---@field name string
---@field view string Raw LuaCATS type text, e.g. "table<string, Lib.Docmap.Node>".
---@field desc string

---One `---@param` on a documented function.
---@class Lib.Docmap.ParamInfo
---@field name string
---@field type string Raw LuaCATS type text.
---@field optional boolean Declared as `name?`.
---@field desc string

---One `---@return` on a documented function. LuaLS allows a bare type with no
---name (`---@return boolean`); `name` is nil in that case.
---@class Lib.Docmap.ReturnInfo
---@field type string Raw LuaCATS type text.
---@field name string?
---@field desc string

---A single documented function, extracted via `lib.nvim.docmap.functions`
---(a `vim.treesitter` query, not `lua-language-server --doc` — see that
---module's header for why). Attached to whichever node owns the file it's
---defined in.
---@class Lib.Docmap.FunctionInfo
---@field name string Qualified name as written, e.g. "M.scan_full" or "M.bar".
---@field signature string Name + parameter list, e.g. "scan_full(opts)".
---@field summary string One-line prose from the doc block, if any.
---@field line integer 1-based line the function definition starts on.
---@field params Lib.Docmap.ParamInfo[]
---@field returns Lib.Docmap.ReturnInfo[]
---@field generic string[] `@generic` type names, if any.
---@field deprecated string? `@deprecated` text; nil when not deprecated.
---@field async boolean
---@field nodiscard boolean
---@field see string[] Raw `@see` targets, unresolved — `docmap.check` validates them.
---@field overload string[] Raw `@overload` signatures, unparsed (rendered as-is).
---@field example string? `@example` block text, if any.
---@field since string? `@since` text, if any.

---A directed type-reference edge: `via` field on the class at `from` has a
---declared type that names the class at `to`. Only present when `opts.luals`
---ran; `ir.edges` is `{}` otherwise (never `nil`, so renderers don't need a
---presence check to iterate it).
---@class Lib.Docmap.Edge
---@field from string Node id owning the referencing class.
---@field to string Node id owning the referenced class.
---@field from_class string Fully-qualified name of the referencing class.
---@field to_class string Fully-qualified name of the referenced class.
---@field via string Field name that carries the reference.

---A drift finding.
---@class Lib.Docmap.Finding
---@field severity Lib.Docmap.Severity
---@field check string Stable check identifier, e.g. "missing-summary".
---@field node string? Node id the finding attaches to.
---@field message string Human-readable description.

---Metadata about a scan. Deliberately carries no timestamp: a generated-at
---field would make every regeneration a diff even when nothing changed, which
---defeats `--check`.
---@class Lib.Docmap.Meta
---@field title string
---@field source string
---@field types_dir string
---@field repo_url string?
---@field branch string
---@field schema integer IR schema version.
---@field counts table<string, integer> Node counts per kind.

---The intermediate representation every renderer and check reads.
---@class Lib.Docmap.IR
---@field meta Lib.Docmap.Meta
---@field root string Root node id.
---@field order string[] All node ids in deterministic walk order.
---@field nodes table<string, Lib.Docmap.Node>
---@field edges Lib.Docmap.Edge[] Type-reference edges from LuaLS enrichment. Always an array, empty when `opts.luals` did not run.

---A live handle returned by `docmap.install()`. Keeps a scanned IR in memory
---and, optionally, keeps it fresh — the object-in-source-code counterpart to
---the file-based `generate()`/`:LibMap` path.
---@class Lib.Docmap.Handle
---@field root string The root this handle was installed for; the registry key.
---@field ir fun(): Lib.Docmap.IR Current IR (already scanned; never triggers a scan itself).
---@field findings fun(): Lib.Docmap.Finding[] Current drift findings.
---@field node fun(id: string): Lib.Docmap.Node? Single node lookup on the current IR.
---@field rescan fun(opts?: { luals?: boolean }): Lib.Docmap.IR, Lib.Docmap.Finding[] Force a rescan now; notifies `on_change` subscribers same as a watch-triggered one.
---@field on_change fun(cb: fun(ir: Lib.Docmap.IR, findings: Lib.Docmap.Finding[])): fun() Subscribe; returns an unsubscribe function.
---@field uninstall fun() Equivalent to `docmap.uninstall(handle)`.

---@class Lib.Docmap
---@field scan fun(opts: Lib.Docmap.Opts): Lib.Docmap.IR
---@field check fun(ir: Lib.Docmap.IR, opts: Lib.Docmap.Opts): Lib.Docmap.Finding[]
---@field scan_full fun(opts: Lib.Docmap.Opts): Lib.Docmap.IR, Lib.Docmap.Finding[] `scan` + optional LuaLS merge (`opts.luals`) + `check`, in one call. What `generate()` and `install()` both build on.
---@field generate fun(opts: Lib.Docmap.Opts): Lib.Docmap.IR, Lib.Docmap.Finding[], string[]
---@field install fun(opts: Lib.Docmap.Opts): Lib.Docmap.Handle
---@field uninstall fun(handle: Lib.Docmap.Handle|string): boolean Accepts a handle or a root path.
---@field render table
