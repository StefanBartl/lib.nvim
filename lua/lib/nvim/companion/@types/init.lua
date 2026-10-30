---@meta
---@module 'lib.nvim.companion.@types'

---@class Lib.Companion.Highlight
---@field line integer # 0-based line
---@field col_start integer # 0-based byte column, inclusive
---@field col_end integer # 0-based byte column, exclusive
---@field group string # highlight group

---@alias Lib.Companion.KeySpec string|{ [1]: string, [integer]: any, prompt?: string }
--- A key in the companion: the action name alone, or the name followed by fixed
--- arguments; `prompt` makes the companion ask for a text (`vim.ui.input`) that is
--- sent as the last argument.

---@class Lib.Companion.OpenOpts
---@field title? string # window / buffer title (default "Companion")
---@field lines? string[] # initial content
---@field highlights? Lib.Companion.Highlight[] # initial extmarks
---@field filetype? string # 'filetype' of the companion buffer
---@field actions? table<string, fun(...: any)> # run in the MAIN instance
---@field keys? table<string, Lib.Companion.KeySpec> # companion keymaps (normal mode) -> action
---@field on_close? fun() # the companion is gone (once)
---@field terminal? string[]|false # argv template with "{cmd}" ("{title}", "{shell}", "{applescript}"); false = no terminal window, a headless companion started directly
---@field attach_timeout? integer|false # ms a companion may take to attach before the handle is closed (default protocol.ATTACH_TIMEOUT_MS); false = no limit
---@field env? Lib.Companion.LaunchEnv # platform facts for the terminal choice (tests)

---@class Lib.Companion.Handle
---@field id integer
---@field update fun(self: Lib.Companion.Handle, lines: string[], highlights?: Lib.Companion.Highlight[]): boolean # replace the content; false once closed
---@field set_title fun(self: Lib.Companion.Handle, title: string): boolean
---@field close fun(self: Lib.Companion.Handle) # idempotent
---@field is_open fun(self: Lib.Companion.Handle): boolean
---@field is_attached fun(self: Lib.Companion.Handle): boolean # the companion has connected

---@class Lib.Companion.WireKey # a key as it travels to the companion (no mixed tables over msgpack)
---@field name string
---@field args any[]
---@field prompt? string

---@class Lib.Companion.Config # what the companion receives when it attaches
---@field title string
---@field filetype? string
---@field keys table<string, Lib.Companion.WireKey>
---@field closed? boolean # the handle was closed before the companion attached: quit

---@class Lib.Companion.Payload # one render pushed to the companion
---@field lines string[]
---@field highlights Lib.Companion.Highlight[]
---@field title string

---@class Lib.Companion.Message # one message for the companion: a Lua chunk + arguments
---@field code string
---@field args any[]

---@class Lib.Companion.Transport # how the registry reaches a companion (a fake in the specs); notifications only, a blocking request across the two channels can deadlock both instances
---@field connect fun(servername: string): integer|nil, string|nil # a channel to the companion's server
---@field notify fun(chan: integer, msg: Lib.Companion.Message): boolean # fire and forget
---@field alive fun(chan: integer): boolean # the channel still exists
---@field close fun(chan: integer)

---@class Lib.Companion.LaunchEnv
---@field os "windows"|"macos"|"linux"
---@field executable fun(name: string): boolean
---@field TERMINAL? string # $TERMINAL

---@class Lib.Companion.InnerOpts
---@field progpath string # vim.v.progpath
---@field root string # the lib.nvim root (holds lua/)
---@field server string # the main's v:servername
---@field id integer
---@field headless? boolean

return {}
