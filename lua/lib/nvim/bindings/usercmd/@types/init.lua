---@meta
---@module 'lib.nvim.bindings.usercmd.@types'

---@class Lib.UserCommand.Args
---@field name string Command name
---@field args string Command arguments
---@field fargs string[] Parsed arguments
---@field bang boolean Whether ! was used
---@field line1 integer Start line
---@field line2 integer End line
---@field range integer Range type
---@field count integer Count modifier
---@field mods string Modifiers
---@field smods table Split modifiers

---@class LibUserCommandOpts
---@field nargs? string|integer
---@field bang? boolean
---@field range? boolean|integer
---@field count? integer
---@field complete? string|fun(arg_lead:string, cmd_line:string, cursor_pos:number):string[]
---@field desc? string
---@field force? boolean # Overwrite an existing command instead of erroring (E174). Default: true.
---@field buffer? boolean|integer # Register buffer-locally via nvim_buf_create_user_command: true = current buffer, or an explicit bufnr. Default: nil (global).
---@field src? string # Override the recorded `file:line`; for a wrapper creating a command on a caller's behalf.

--- One user command as it was actually created, recorded by
--- `lib.nvim.bindings.usercmd.create`. Read it back with `registered()`.
---@class Lib.UserCommand.Record
---@field name string
---@field desc string|nil
---@field nargs string|integer|nil
---@field bang boolean
---@field range boolean
---@field complete string|nil       # The completion kind, or "<function>" for a custom one.
---@field buffer boolean|integer|nil
---@field src string                # "file:line" of the call site, so the answer says where to look

---@class Lib.UsrCmd
---@field create fun(name: string, callback: string|fun(args:Lib.UserCommand.Args), opts: LibUserCommandOpts|nil): nil
---@field delete fun(name: string, bufnr: integer|nil): boolean # Delete a command AND forget its record
---@field registered fun(filter: { name?: string, buffer?: integer|boolean }|nil): Lib.UserCommand.Record[]
---@field docs Lib.UserCommand.Docs
---@field composer Lib.UserCmd.Composer # subcommand composer (:Verb sub … + completion + docgen)

---@class Lib.UserCommand.Docs.Opts
---@field dir? string    # Target directory. Inferred from the caller's repo when omitted.
---@field root? string   # Repository root; records from elsewhere are filtered out.
---@field note? string   # Extra paragraph for the header.
---@field filter? fun(r: Lib.UserCommand.Record): boolean

---@class Lib.UserCommand.Docs
---@field write fun(opts: Lib.UserCommand.Docs.Opts|nil): boolean, string|nil, string[]
---@field check fun(opts: Lib.UserCommand.Docs.Opts|nil): boolean, string[]
---@field create_usercmd fun(name: string|nil): nil

return {}
