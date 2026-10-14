---@meta
---@module 'lib.nvim.contract.errors.@types'

---@class Lib.Contract.Error
---@field code string
---@field message string
---@field retryable boolean
---@field details? table

---One text pattern: a message that contains one of the plain strings in `find` gets `code`.
---@class Lib.Contract.ErrorPattern
---@field code string
---@field find string[]
---@field retryable? boolean

---@class Lib.Contract.ClassifyOpts
---@field patterns? Lib.Contract.ErrorPattern[]  The plugin's own message patterns, tried before the built-in ones.
---@field detail_keys? string[]                  Keys of `info` a document may show (default `M.DETAIL_KEYS`).

---@class Lib.Contract.Errors
---@field CODES string[]
---@field DETAIL_KEYS string[]
---@field fail fun(code: string, message: string, retryable?: boolean): Lib.Contract.Error
---@field scrub fun(text: string): string
---@field text fun(value: any): string
---@field check_patterns fun(patterns: any): string|nil
---@field classify fun(err: any, info?: table, opts?: Lib.Contract.ClassifyOpts): Lib.Contract.Error

return {}
