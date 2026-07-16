---@meta
---@module 'lib.lua.uuid.@types'

---@alias Lib.Uuid.Style "compact"|"upper"|"braced"

---@class LibUuid
---@field generate fun(): string # Generate a lowercase, hyphenated UUIDv4 string.
---@field format fun(uuid: string, style?: Lib.Uuid.Style): string # Transform a UUID's presentation without validating its shape.
---@field get fun(style?: Lib.Uuid.Style): string # Convenience: format(generate(), style).
