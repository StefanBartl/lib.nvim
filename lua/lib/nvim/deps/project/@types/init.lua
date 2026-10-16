---@meta
---@module 'lib.nvim.deps.project.@types'

---What a scan of one root found: how many files of each kind, nothing else.
---A "key" is `"*.lua"` for a file with an extension (the last one, lower-cased)
---or the bare file name (`"Makefile"`, `".gitignore"`) for one without.
---@class Lib.Deps.Project.KeyCount
---@field count integer files of this kind
---@field sample string one real path of this kind (what `vim.filetype.match` is asked about)

---@class Lib.Deps.Project.Scan
---@field root string normalized root that was walked
---@field total integer files seen
---@field keys table<string, Lib.Deps.Project.KeyCount>
---@field errors string[]|nil directories that could not be read ("<dir>: <reason>")
---@field at integer `os.time()` the walk finished (the cache ages from here)

---@class Lib.Deps.Project.ScanOpts
---@field refresh? boolean walk again even if a cached scan of this root is fresh
---@field ttl_seconds? integer how long a cached scan of one root is trusted; default 600
---@field ignore? fun(abs_path: string, is_dir: boolean): boolean prune entries (a directory prunes its subtree); default: `lib.nvim.fs.ignore.list` basenames

---A tool the CALLER says a filetype wants, installed from a Mason package.
---@class Lib.Deps.Project.MasonTool
---@field mason string Mason package name (`stylua`, `lua-language-server`)
---@field why? string one sentence for the report

---@alias Lib.Deps.Project.ToolEntry Lib.Deps.Tool|Lib.Deps.Project.MasonTool

---What the caller maps: filetype -> tools that filetype wants.
---@alias Lib.Deps.Project.ToolMap table<string, Lib.Deps.Project.ToolEntry[]>

---@class Lib.Deps.Project.ReportOpts
---@field tools? Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap tools in addition to everything `register_tools` holds
---@field registered? boolean false: ignore what `register_tools` holds (default true)

---One treesitter language the root's files need.
---@class Lib.Deps.Project.Language
---@field lang string treesitter language name
---@field filetypes string[] the filetypes that resolved to it
---@field files integer files of those filetypes
---@field state "installed"|"available"|"unavailable"|"unknown"|"declined" `parser_policy.status`, or `"declined"` for an installable parser the user answered "Never" to

---One tool a filetype in the root wants.
---@class Lib.Deps.Project.ToolStatus
---@field id string `bin` (kind `bin`) or the Mason package name (kind `mason`)
---@field kind "bin"|"mason"
---@field tool Lib.Deps.Project.ToolEntry
---@field filetypes string[] wanted for these filetypes (those present in the root)
---@field files integer files of those filetypes
---@field state "present"|"missing"|"unknown"|"unavailable" `unknown`: Mason is not loadable; `unavailable`: Mason does not list the package

---@class Lib.Deps.Project.Report
---@field root string
---@field total integer files seen
---@field errors string[]|nil
---@field languages Lib.Deps.Project.Language[] most files first
---@field missing_parsers Lib.Deps.Project.Language[] subset of `languages`: installable and not installed (state `available` or `declined`)
---@field tools Lib.Deps.Project.ToolStatus[]
---@field missing_tools Lib.Deps.Project.ToolStatus[] subset of `tools` with state `missing`
---@field unmapped integer files whose kind resolved to no filetype
---@field problems string[] caller-supplied tool entries that were skipped, and why

---@class Lib.Deps.Project.InstallPlan
---@field parsers string[] languages to hand to `parser_policy.install`
---@field mason string[] Mason packages to install through the registry API
---@field tools Lib.Deps.Tool[] missing `bin` tools, handed to `deps.install` (a terminal the user submits)
---@field plan Lib.Deps.Plan|nil `deps.install.plan(tools)`, nil when there are no `bin` tools
---@field declined string[] installable languages left out because the user said "Never"
---@field text string the confirmation text
---@field empty boolean nothing to install

---@class Lib.Deps.Project.InstallOpts
---@field confirm? boolean false: skip the question (callers that asked in their own UI, and tests); the terminal command is still only typed, never submitted
---@field manager? Lib.Deps.Manager package manager override, as for `deps.install.plan`

---@class Lib.Deps.Project.SetupOpts
---@field auto? boolean scan the current directory now and on every `DirChanged`, and notify once per root when something is missing. Default false.
---@field ttl_seconds? integer passed to every scan the trigger starts
---@field tools? Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap passed to every report the trigger builds

---`lib.nvim.deps.project` module surface.
---@class Lib.Deps.Project
---@field key_of fun(path: string): string
---@field count fun(root: string, paths: string[], errors?: string[]|nil): Lib.Deps.Project.Scan
---@field scan fun(root: string, opts: Lib.Deps.Project.ScanOpts|nil, on_done: fun(scan: Lib.Deps.Project.Scan)): fun()
---@field forget fun(root?: string): nil
---@field register_tools fun(owner: string, tools: Lib.Deps.Project.ToolMap|fun(): Lib.Deps.Project.ToolMap): fun()
---@field registered fun(): string[]
---@field report fun(scan: Lib.Deps.Project.Scan, opts?: Lib.Deps.Project.ReportOpts): Lib.Deps.Project.Report
---@field lines fun(report: Lib.Deps.Project.Report, opts?: Lib.Deps.ManagerOpts): string[]
---@field summary fun(report: Lib.Deps.Project.Report): string|nil
---@field install_plan fun(report: Lib.Deps.Project.Report, opts?: Lib.Deps.ManagerOpts): Lib.Deps.Project.InstallPlan
---@field install fun(report: Lib.Deps.Project.Report, opts?: Lib.Deps.Project.InstallOpts): { parsers: string[], mason: string[], terminal: boolean }|nil
---@field run fun(root?: string, action?: "refresh"|"install", opts?: Lib.Deps.Project.ReportOpts): nil
---@field setup fun(opts?: Lib.Deps.Project.SetupOpts): nil
---@field reset_announced fun(): nil

return {}
