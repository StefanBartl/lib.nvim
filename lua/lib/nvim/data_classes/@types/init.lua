---@meta
---@module 'lib.nvim.data_classes.@types'

---The class an area has in `areas.json`.
---@alias Lib.DataClasses.Class "public"|"internal"|"private"

---The class an area is shown with: its class, or `"unclassified"` when nothing decides it (released for nothing).
---@alias Lib.DataClasses.Shown "public"|"internal"|"private"|"unclassified"

---Why a file could not be used: `"unreadable"` (exists, cannot be read or is not UTF-8), `"invalid"` (read, but not a
---file of schema 1 or 2), `"no_config_dir"` (the config folder of the app cannot be told on this machine).
---@alias Lib.DataClasses.ProblemKind "unreadable"|"invalid"|"no_config_dir"

---One entry of the file.
---@class Lib.DataClasses.Entry
---@field class Lib.DataClasses.Class
---@field repo? string  The repository folder of the area (a plain name), if the file names one.

---Where `areas.json` is looked for. Without any field: `<config dir of tasks-desktop>/areas.json`.
---@class Lib.DataClasses.Opts
---@field path? string  The file itself (wins over everything else).
---@field dir? string  A config folder: the file is `<dir>/areas.json`.
---@field app? string  The folder name of the app under the system config folder (default `"tasks-desktop"`).
---@field env_var? string  The variable that names the config folder (default `"TASKS_DESKTOP_CONFIG_DIR"`); an empty value is not set.
---@field env? table<string, string>  The environment to read instead of the process's (for specs).
---@field os? "windows"|"macos"|"linux"  The system to resolve for instead of this one (for specs); anything but Windows and macOS is resolved like Linux.
---@field vault? string  `class_of_repo` only: look in this vault alone (default: every vault of the file, the strictest class wins).

---An area that names a repository, as `class_of_repo` found it.
---@class Lib.DataClasses.Match
---@field vault string
---@field area string
---@field class Lib.DataClasses.Class
---@field by "repo"|"name"  Named through its `repo` field, or (without one) by an area name equal to the repository.

---What the file says for one vault (`AreaPolicy` of classes.rs).
---@class Lib.DataClasses.Policy
---@field shown fun(self: Lib.DataClasses.Policy, area: string): Lib.DataClasses.Shown
---@field allows fun(self: Lib.DataClasses.Policy, area: string): boolean  May the area leave the machine? Only `public` and `internal`.
---@field entry fun(self: Lib.DataClasses.Policy, area: string): Lib.DataClasses.Entry|nil  A copy of the entry, if the file has one.
---@field repo_of fun(self: Lib.DataClasses.Policy, area: string): string|nil
---@field default fun(self: Lib.DataClasses.Policy): Lib.DataClasses.Class|nil  The class of an area without an entry, if the owner chose one.
---@field areas fun(self: Lib.DataClasses.Policy): string[]  The names of the entries, sorted by byte value.
---@field unclassified fun(self: Lib.DataClasses.Policy, all: string[]): string[]  The areas of `all` that nothing decides, in the order of `all`.
---@field private_areas fun(self: Lib.DataClasses.Policy, all: string[]): string[]  The areas of `all` that are private, in the order of `all`.
---@field len fun(self: Lib.DataClasses.Policy): integer  How many entries.
---@field is_empty fun(self: Lib.DataClasses.Policy): boolean

---What the file says for every vault (`Classes` of classes.rs). A file that cannot be used is one in which nothing is
---classified, with `problem` set.
---@class Lib.DataClasses.Classes
---@field problem string|nil  Why the file could not be used (no path in it); `nil` for a usable file and for no file.
---@field kind Lib.DataClasses.ProblemKind|nil  The kind of `problem`.
---@field missing boolean  There is no file (nothing is classified, and that is not a problem).
---@field path string|nil  The file that was looked at.
---@field schema integer|nil  The schema of a usable file.
---@field for_vault fun(self: Lib.DataClasses.Classes, vault?: string): Lib.DataClasses.Policy  A vault the file does not name classifies nothing. Default `"main"`.
---@field shown fun(self: Lib.DataClasses.Classes, area: string, vault?: string): Lib.DataClasses.Shown
---@field allows fun(self: Lib.DataClasses.Classes, area: string, vault?: string): boolean
---@field vaults fun(self: Lib.DataClasses.Classes): string[]  The vaults the file names, sorted.
---@field class_of_repo fun(self: Lib.DataClasses.Classes, repo: string, vault?: string): Lib.DataClasses.Shown, Lib.DataClasses.Match[]

---@class Lib.DataClasses
---@field SCHEMA integer
---@field SCHEMA_VAULTS integer
---@field MAX_AREAS integer
---@field MAX_FILE_BYTES integer
---@field MAIN_VAULT string
---@field APP string
---@field ENV_VAR string
---@field FILE string
---@field config_dir fun(opts?: Lib.DataClasses.Opts): string|nil, string|nil
---@field path fun(opts?: Lib.DataClasses.Opts): string|nil, string|nil
---@field parse fun(text: string): Lib.DataClasses.Classes
---@field load fun(opts?: Lib.DataClasses.Opts): Lib.DataClasses.Classes, string|nil
---@field class_of_repo fun(repo: string, opts?: Lib.DataClasses.Opts): Lib.DataClasses.Shown, string|nil, Lib.DataClasses.Match[]
---@field valid_area_name fun(name: string): boolean, string|nil
---@field valid_vault_name fun(name: string): boolean, string|nil

return {}
