---@meta
---@module 'lib.nvim.buffer.@types'

---@class Lib.Buffer.Query
---@field is_markdown_buf fun(bufnr_arg: integer|nil): integer|nil

---@class Lib.Buffer.Modify
---@field insert_lines fun(lines: string[], pos?: Lib.Buf.InsertLinesPos): nil

---@alias Lib.Buffer.OpenBackground fun(path: string, opts?: { load?: boolean }): boolean, integer|string

---@class Lib.Buffer
---@field query Lib.Buffer.Query
---@field modify Lib.Buffer.Modify
---@field open_background Lib.Buffer.OpenBackground

---@class Lib.Buffer.ALL
---@field is_markdown_buf fun(bufnr_arg: integer|nil): integer|nil
---@field insert_lines fun(lines: string[], pos?: Lib.Buf.InsertLinesPos): nil
---@field open_background Lib.Buffer.OpenBackground

return {}

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
