---@meta
---@module 'lib.lua.memo.@types'

---@class Lib.Memo.LruNode
---@field key any
---@field value any
---@field prev Lib.Memo.LruNode|nil
---@field next Lib.Memo.LruNode|nil

---@class Lib.Memo.LruState
---@field cap integer
---@field size integer
---@field map table<any, Lib.Memo.LruNode>
---@field head Lib.Memo.LruNode|nil
---@field tail Lib.Memo.LruNode|nil

---@class Lib.Memo.Lru : Lib.Memo.LruState
---@field get fun(self: Lib.Memo.Lru, key: any): any|nil
---@field put fun(self: Lib.Memo.Lru, key: any, value: any)
---@field _move_front fun(self: Lib.Memo.Lru, node: Lib.Memo.LruNode)
---@field _evict fun(self: Lib.Memo.Lru)

--- `weak` used to be listed here as a supported mode. It was never read, and
--- could not have worked: `memoize` keys on the string a keyer returns, and a
--- weak table does not collect string keys. `memo.fn` rejects unknown options
--- now instead of ignoring them.
---@class Lib.Memo.MemoOpts
---@field size integer|nil # Cache capacity (default: 128)
---@field keyer fun(...): string|nil # Custom key generator (default: type-tagged tostring per argument)

---@class Lib.Memo.Memo
---@field memoize fun(fn: fun(...): any, cap: integer|nil, keyer: fun(...): string|nil): fun(...): any
---@field memoize2 fun(fn: fun(...): any, cap: integer|nil, keyer: fun(...): string|nil): fun(...): any # As `memoize`, but the default keyer serializes table arguments

---@class Lib.Memo
---@field lru table # LRU cache constructor module
---@field memo Lib.Memo.Memo # Memoization helper module
---@field fn fun(func: fun(...): any, opts: Lib.Memo.MemoOpts|nil): fun(...): any # Convenience wrapper

return {}
