---@meta
---@module 'lib.nvim.usercmd.composer.@types'

--- Built-in argument type names. Custom types registered via
--- `composer.register_type` extend this set at runtime.
---@alias Lib.UserCmd.Composer.ArgType
---| "STRING"
---| "INT"
---| "FLOAT"
---| "BOOL"
---| "PATH"
---| "DIR"
---| "FILE"
---| "BUFFER"

--- One positional argument that follows a route's literal path.
---@class Lib.UserCmd.Composer.ArgSpec
---@field name      string                          # shown in usage/help/docs
---@field type?     Lib.UserCmd.Composer.ArgType    # default "STRING"
---@field enum?     string[]                        # closed set; overrides type for completion + validation
---@field values?   string[]                        # completion-only hints for a STRING arg (not enforced)
---@field optional? boolean                         # default false
---@field default?  any                             # value bound when an optional arg is omitted

--- One `--flag` accepted by a route, parsed out of its token tail before
--- positional binding. Opt-in per route: a route with no `flags` behaves
--- exactly as before (a leading "--" is just an ordinary positional token).
---@class Lib.UserCmd.Composer.FlagSpec
---@field name        string                          # matched as --name / --name=value
---@field short?      string                          # single-char alias matched as -x (e.g. short="r" for -r); next-token-value form only, no -x=value
---@field type?       Lib.UserCmd.Composer.ArgType    # value type; default "STRING". Ignored when bool=true
---@field bool?       boolean                         # presence-only flag, no value consumed, e.g. --dry
---@field enum?       string[]                        # closed set for the value (ignored when bool=true)
---@field repeatable? boolean                         # collect every occurrence into an array (ctx.flags.name = {...})
---@field default?    any                             # value bound when the flag is never passed

--- One bare `key=value` pair (no dashes) accepted by a route, parsed out of
--- its token tail before positional binding. Opt-in per route: an
--- undeclared key is left as an ordinary positional, not an error (see
--- kv.lua) — "=" is too common in legitimate positional values to treat
--- every match as intentional.
---@class Lib.UserCmd.Composer.KvSpec
---@field key     string                          # matched as key=value
---@field type?   Lib.UserCmd.Composer.ArgType    # value type; default "STRING"
---@field enum?   string[]                        # closed set for the value; validated + completed (see argtypes.validate)
---@field values? string[]                        # completion-only hints for a STRING value (not enforced, unlike enum) — same argtypes.STRING.complete a plain ArgSpec uses
---@field default? any                            # value bound when the key is never passed

--- A single command route: a literal token path, an optional positional arg
--- schema, optional flags, and the handler.
---@class Lib.UserCmd.Composer.Route
---@field path   string[]                            # literal subcommand tokens, e.g. { "surround", "quote" }. `{}` = the verb's root route (args/flags parsed even with no literal subcommand, e.g. `:Replace {old} {new} --dry`)
---@field args?  Lib.UserCmd.Composer.ArgSpec[]      # positional args accepted after the path
---@field flags? Lib.UserCmd.Composer.FlagSpec[]     # --flag / --flag=value accepted anywhere in the tail, in any order
---@field kv?    Lib.UserCmd.Composer.KvSpec[]       # bare key=value pairs (no dashes) accepted anywhere in the tail
---@field run    fun(ctx: Lib.UserCmd.Composer.Ctx)|string  # handler, or a module path returning a callable / { run = fn }
---@field desc?  string
---@field bang?  boolean                             # honor :Verb! for this route
---@field range? boolean|integer
---@field count? integer                             # accept a :N Verb count prefix, defaulting to this value when omitted (see nvim_create_user_command's `count`)

--- The full spec passed to `composer.verb(name, spec)`.
---@class Lib.UserCmd.Composer.Spec
---@field desc?    string                                    # verb description (docs + :command listing)
---@field default? fun(ctx: Lib.UserCmd.Composer.Ctx)        # handler for the bare `:Verb` (no tokens)
---@field routes?  Lib.UserCmd.Composer.Route[]
---@field bang?    boolean                                   # allow the bang form at the command level (default: true if any route uses it)
---@field range?   boolean|integer                           # allow a range at the command level
---@field count?   integer                                   # allow a :N Verb count prefix at the command level, default value when omitted
---@field buffer?  boolean|integer                           # register buffer-locally: true = current buffer, or an explicit bufnr. Default: nil (global)

--- Handler context. Carries coerced args plus the raw command modifiers so
--- migrated commands keep range/bang/count behavior.
---@class Lib.UserCmd.Composer.Ctx
---@field args   table<string, any>                  # coerced positional args, keyed by ArgSpec.name
---@field pos    any[]                               # coerced positional args, in order
---@field flags  table<string, any>                  # coerced --flag values, keyed by FlagSpec.name (true for bare bool flags, array for repeatable)
---@field kv     table<string, any>                  # coerced key=value pairs, keyed by KvSpec.key
---@field rest   string[]                            # leftover tokens beyond the declared schema
---@field bang   boolean
---@field range  { line1: integer, line2: integer, count: integer, range: integer }
---@field path   string[]                            # the literal path that matched
---@field raw    Lib.UserCommand.Args                # the untouched nvim callback args

--- A registered argument type: a validator and a completer.
---@class Lib.UserCmd.Composer.TypeDef
---@field validate fun(raw: string, spec: Lib.UserCmd.Composer.ArgSpec): boolean, any, string|nil  # ok, value, err
---@field complete? fun(arg_lead: string, spec: Lib.UserCmd.Composer.ArgSpec): string[]

--- Handle returned by `composer.verb(...)` / `:build()`.
---@class Lib.UserCmd.Composer.Handle
---@field name     fun(self: Lib.UserCmd.Composer.Handle): string
---@field spec     fun(self: Lib.UserCmd.Composer.Handle): Lib.UserCmd.Composer.Spec
---@field document fun(self: Lib.UserCmd.Composer.Handle, path?: string): boolean, string|nil
--- Fluent builders additionally expose :desc/:default/:route/:bang/:range/:build.

--- Docs configuration (see `composer.setup`).
---@class Lib.UserCmd.Composer.DocsOpts
---@field path? string                               # default output file (default: docs/BINDINGS/Usercmds.md)
---@field mode? "replace"|"section"                  # overwrite whole file, or update a delimited block (default: "replace")

---@class Lib.UserCmd.Composer.SetupOpts
---@field docs? Lib.UserCmd.Composer.DocsOpts

---@class Lib.UserCmd.Composer
---@field verb          fun(name: string, spec?: Lib.UserCmd.Composer.Spec): Lib.UserCmd.Composer.Handle
---@field document      fun(path?: string): boolean, string|nil
---@field setup         fun(opts?: Lib.UserCmd.Composer.SetupOpts)
---@field register_type fun(name: string, def: Lib.UserCmd.Composer.TypeDef)
---@field registry      fun(): table<string, Lib.UserCmd.Composer.Handle>

return {}
