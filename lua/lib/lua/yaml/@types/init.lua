---@meta
---@module 'lib.lua.yaml.@types'

---@class LibYaml
---@field simple_parse fun(text: string): table|nil, string|nil # Decode a minimal YAML-ish subset into a nested Lua table, or nil + err message on malformed indentation.
