---@meta
---@module 'lib.nvim.buffer.@types'

---@class Lib.Buffer.Query
---@field is_markdown_buf fun(bufnr_arg: integer|nil): integer|nil

---@class Lib.Buffer.Modify
---@field insert_lines fun(lines: string[], pos?: Lib.Buf.InsertLinesPos): nil

---@alias Lib.Buffer.OpenBackground fun(path: string, opts?: { load?: boolean }): boolean, integer|string

--- CDX: `Lib.Buffer`/`Lib.Buffer.ALL` document a `require("lib.nvim.buffer")`
--- aggregator that does not exist in the tree (no `buffer/init.lua`); the
--- real `Lib` aggregate flattens these functions directly instead (see
--- `lib/@types/all_functions.lua`). Same stale-aggregator pattern already
--- flagged on `Lib.Modules` in `lib/@types/init.lua`.
---@class Lib.Buffer
---@field query Lib.Buffer.Query
---@field modify Lib.Buffer.Modify
---@field open_background Lib.Buffer.OpenBackground

---@class Lib.Buffer.ALL
---@field is_markdown_buf fun(bufnr_arg: integer|nil): integer|nil
---@field insert_lines fun(lines: string[], pos?: Lib.Buf.InsertLinesPos): nil
---@field open_background Lib.Buffer.OpenBackground

---@class Lib.Buf.InsertLinesPosCursor
---@field cursor true

---@class Lib.Buf.InsertLinesPosRowCol
---@field row integer 0-based row index
---@field col? integer optional column (used only for cursor placement)

---@class Lib.Buf.InsertLinesPosColRow
---@field col integer
---@field row integer

---@class Lib.Buf.InsertLinesPosKeyword
---@field position '"start"|"end"'

---@alias Lib.Buf.InsertLinesPos
---| Lib.Buf.InsertLinesPosCursor
---| Lib.Buf.InsertLinesPosRowCol
---| Lib.Buf.InsertLinesPosColRow
---| Lib.Buf.InsertLinesPosKeyword

return {}
