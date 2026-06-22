---@meta
---@module 'lib.nvim.usercmd.@types'

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
---@field force? boolean

---@class Lib.UsrCmd
---@field create fun(name: string, callback: string|fun(args:Lib.UserCommand.Args), opts: LibUserCommandOpts|nil): nil

return {}
