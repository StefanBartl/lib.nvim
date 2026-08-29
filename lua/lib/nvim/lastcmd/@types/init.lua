---@meta
---@module 'lib.nvim.lastcmd.@types'

---Captured shape of a Visual selection, so a Visual-mode mapping can be
---replayed against an equally-sized selection starting at the cursor.
---@class Lib.Lastcmd.Visual
---@field kind "v"|"V"|"b" # charwise / linewise / blockwise
---@field lines? integer # `V`, and blockwise: how many lines the selection spanned
---@field cols? integer # `v` on one line, and blockwise: column span
---@field rows? integer # `v` across lines: how many rows it spanned
---@field scol? integer # `v` across lines: start column
---@field ecol? integer # `v` across lines: end column

---@class Lib.Lastcmd.Entry
---@field keys string # Mapping lhs in `keytrans` notation, e.g. `<M-Right>`
---@field count string # Literal count prefix as typed (`""` when none)
---@field mode "n"|"x" # Which mapping mode matched
---@field visual? Lib.Lastcmd.Visual # Present only for `x`-mode entries

---@class Lib.Lastcmd.Opts
---@field experimental? boolean|string # Opt-in. `nil`/`false` off (and undoes an earlier setup), `true` on at the default lhs (`<M-.>`), a string on at that lhs.
---@field ignore? string[] # Extra mapping lhs values to treat as motions (never recorded), in `keytrans` notation.
---@field motions? boolean # `false` drops the built-in motion denylist entirely. Default `true`.

---@class Lib.Lastcmd
---@field setup fun(opts?: Lib.Lastcmd.Opts): boolean # Enable the feature and bind its trigger. Off unless `opts.experimental`. Idempotent.
---@field repeat_last fun(): boolean # Re-run the last real command. Returns whether anything ran.
---@field peek fun(): Lib.Lastcmd.Entry|nil # The recorded mapping entry, if any -- inspection/tests.
---@field clear fun() # Forget the recorded mapping and all per-buffer tick bookkeeping.
---@field enabled fun(): boolean # Whether the tracker is currently installed.
---@field trigger_key fun(): string|nil # The lhs the trigger is bound to, or `nil` when off.
---@field teardown fun() # Remove the `on_key` tracker and the trigger keymap.

return {}
