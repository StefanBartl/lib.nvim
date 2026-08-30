---@meta
---@module 'lib.nvim.deps.@types'

---Per-package-manager package name for one tool. Keys are package-manager
---ids (`apt`, `dnf`, `pacman`, `zypper`, `apk`, `brew`, `winget`, `scoop`,
---`choco`); values are that manager's package name. A missing key means "no
---known package on that manager", not "impossible" — `has_exec` detection
---still works for a tool with an empty `pkg` map, install offers just won't
---cover every manager.
---@alias Lib.Deps.PkgMap table<string, string>

---One tool requirement, parsed from either a ```install-tool fenced block
---(`docs/INSTALL.md`) or a `tools[]` array entry (`docs/install.json`).
---@class Lib.Deps.Tool
---@field bin string canonical executable name: the tool's identity, its display label, the key its install state is stored under, and what `pkg` maps from
---@field bin_alternatives string[]|nil other names the SAME tool is installed as on some platform (`gs` -> `gswin64c`, `gswin32c`). Detection only -- see `lib.nvim.deps.detect`. Not a list of substitutes: a different program that would also do the job is a different tool.
---@field required boolean true when the plugin cannot function at all without it
---@field why string one-sentence reason this tool matters (validation requires non-empty)
---@field see string|nil optional anchor/link into the plugin's own docs for more detail
---@field pkg Lib.Deps.PkgMap package name per package manager (validation requires >= 1 entry)

---One validation problem found while parsing a spec file.
---@class Lib.Deps.Error
---@field index integer 1-based position of the offending tool entry; 0 for a file-level problem (e.g. malformed JSON/YAML, not a list)
---@field field string|nil the offending field name, when attributable to one
---@field message string human-readable description

---Result of parsing + validating one spec file (`docs/INSTALL.md` or `docs/install.json`).
---@class Lib.Deps.ParseResult
---@field tools Lib.Deps.Tool[] entries that passed validation
---@field errors Lib.Deps.Error[] entries (or the whole file) that did not; empty on a fully clean parse

---@class Lib.Deps.HealthEntry
---@field bin? string executable name, probed via `has_exec` (mutually exclusive with `python_module`)
---@field bin_alternatives? string[] other names the same executable goes by on some platform; only meaningful alongside `bin`
---@field python_module? string Python module name, probed via `python -c "import <module>"` (mutually exclusive with `bin`)
---@field required? boolean reported as an error (not a warning) when missing; defaults to false
---@field label? string display label; defaults to `bin`/`python_module`
---@field hint? string human install hint shown alongside a missing report (e.g. "pip install pdfplumber")

---`lib.nvim.deps.spec` module surface: parse/validate/find spec files.
---@class Lib.Deps.Spec
---@field parse_markdown fun(text: string): Lib.Deps.ParseResult
---@field parse_json fun(text: string): Lib.Deps.ParseResult
---@field load fun(path: string): Lib.Deps.ParseResult|nil, string|nil
---@field find fun(plugin_name: string): string|nil path to the resolved spec file, or nil if none found
---@field plugins fun(): string[] names of every plugin on runtimepath shipping a deps spec

---`lib.nvim.deps.health` module surface: generic `check_exe`/`probe` replacement.
---@class Lib.Deps.Health
---@field report fun(entries: Lib.Deps.HealthEntry[]): nil
---@field from_tools fun(tools: Lib.Deps.Tool[]): nil report health directly from a parsed spec's `tools`
---@field report_for fun(plugin_name: string): nil locate + report a plugin's own spec, plus a pointer to `:Lib deps show`

---One OS package manager: how to detect it and how to compose an install command.
---@class Lib.Deps.Manager
---@field id string manager id, matching the keys used in a tool's `pkg` map (`apt`, `brew`, …)
---@field bin string executable probed to decide whether this manager is present
---@field install string[] argv tokens between the binary and the package names (e.g. `{"install"}`, `{"-S","--needed"}`)
---@field needs_root boolean true when the command must be run as root (prefixed with `sudo` where available)
---@field multi boolean true when one invocation accepts several packages; false forces one command per package (winget)

---What installing a tool list would involve on this host.
---@class Lib.Deps.Plan
---@field manager Lib.Deps.Manager|nil detected (or overridden) package manager; nil when none is present
---@field present Lib.Deps.Tool[] tools already found on PATH
---@field missing Lib.Deps.Tool[] tools not found on PATH
---@field installable Lib.Deps.Tool[] subset of `missing` this manager has a package name for
---@field unsupported Lib.Deps.Tool[] subset of `missing` with no package name for this manager
---@field packages string[] package names for `installable`, in the same order
---@field commands string[][] argv list(s) that would install `packages`; more than one only for managers with `multi = false`

---`lib.nvim.deps.pm` module surface: package-manager detection + command composition.
---@class Lib.Deps.Pm
---@field get fun(id: string): Lib.Deps.Manager|nil
---@field ids fun(): string[]
---@field available fun(): Lib.Deps.Manager[]
---@field detect fun(): Lib.Deps.Manager|nil
---@field commands fun(manager: Lib.Deps.Manager, packages: string[]): string[][]
---@field render fun(argv: string[]): string
---@field is_root fun(): boolean
---@field needs_terminal fun(manager: Lib.Deps.Manager): boolean

---`lib.nvim.deps.detect` module surface: does a declared tool exist on this
---host, under any of the names it goes by?
---@class Lib.Deps.Detect
---@field names fun(tool: Lib.Deps.Tool|Lib.Deps.HealthEntry): string[] every name the tool may be found under, canonical first
---@field found_as fun(tool: Lib.Deps.Tool|Lib.Deps.HealthEntry): string|nil the name it was found under, nil when absent
---@field found fun(tool: Lib.Deps.Tool|Lib.Deps.HealthEntry): boolean
---@field forget fun(tool: Lib.Deps.Tool|Lib.Deps.HealthEntry): nil drop the memoized PATH result for every one of its names

---`lib.nvim.deps.install` module surface: plan computation + confirmed terminal handoff.
---@class Lib.Deps.Install
---@field plan fun(tools: Lib.Deps.Tool[], opts?: { manager?: Lib.Deps.Manager }): Lib.Deps.Plan
---@field run fun(plan: Lib.Deps.Plan, opts?: { confirm?: boolean }): boolean

---Live install state for one tool, keyed by `tool.bin` in `deps.view`'s
---`ui` tables.
---@class Lib.Deps.View.ToolUiState
---@field lines string[] streamed stdout/stderr lines, in arrival order
---@field running boolean
---@field done boolean
---@field exit_code integer|nil
---@field collapsed boolean

---`lib.nvim.deps.first_run` module surface: show a plugin's deps popup once
---ever, persisted across restarts.
---@class Lib.Deps.FirstRun
---@field seen fun(plugin_name: string, cache_opts?: Lib.Cache.Opts): boolean
---@field mark_seen fun(plugin_name: string, cache_opts?: Lib.Cache.Opts)
---@field reset fun(plugin_name?: string, cache_opts?: Lib.Cache.Opts)
---@field show_once fun(plugin_name: string, opts?: { manager?: Lib.Deps.Manager, cache?: Lib.Cache.Opts }): boolean

---`lib.nvim.deps.view` module surface: render/show a plugin's tool report.
---@class Lib.Deps.View
---@field render fun(plugin_name: string, result: Lib.Deps.ParseResult, opts?: { manager?: Lib.Deps.Manager }, ui?: table<string, Lib.Deps.View.ToolUiState>): { lines: string[], line_tools: (Lib.Deps.Tool|nil)[] }
---@field lines fun(plugin_name: string, result: Lib.Deps.ParseResult, opts?: { manager?: Lib.Deps.Manager }): string[]
---@field show_split fun(plugin_name: string, result: Lib.Deps.ParseResult): integer, integer
---@field show fun(plugin_name: string, result: Lib.Deps.ParseResult, opts?: { manager?: Lib.Deps.Manager }): integer, integer

---`lib.nvim.deps` module surface.
---@class Lib.Deps
---@field spec Lib.Deps.Spec
---@field detect Lib.Deps.Detect
---@field health Lib.Deps.Health
---@field pm Lib.Deps.Pm
---@field install Lib.Deps.Install
---@field view Lib.Deps.View
---@field first_run Lib.Deps.FirstRun
---@field show_once fun(plugin_name: string, opts?: { manager?: Lib.Deps.Manager, cache?: Lib.Cache.Opts }): boolean
---@field plugins fun(): string[] every plugin on runtimepath shipping a deps spec
---@field show fun(plugin_name: string): boolean render one plugin's tool report in a scratch split
---@field install_for fun(plugin_name: string): boolean plan + confirm + hand off to a terminal
---@field routes fun(): table[] the `:Lib deps …` routes, for `lib.nvim_usrcmds` to merge into the `:Lib` verb

return {}
