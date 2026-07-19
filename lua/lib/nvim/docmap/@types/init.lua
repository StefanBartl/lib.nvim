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

---@class Lib.Docmap
---@field scan fun(opts: Lib.Docmap.Opts): Lib.Docmap.IR
---@field check fun(ir: Lib.Docmap.IR, opts: Lib.Docmap.Opts): Lib.Docmap.Finding[]
---@field generate fun(opts: Lib.Docmap.Opts): Lib.Docmap.IR, Lib.Docmap.Finding[]
---@field render table
