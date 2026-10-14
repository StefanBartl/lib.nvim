---@meta
---@module 'lib.nvim.contract.host.@types'

---@class Lib.Contract.HostConfig
---@field api Lib.Contract.Api                              # The dispatcher (`lib.nvim.contract.api`).
---@field protocol? integer                                 # The version of the line protocol (the number after `ready`), default 1.
---@field call_opts? table|fun(): table                     # The options of every `api.call` (the plugin finds its source from them or from its environment). A function is asked per request.

---@class Lib.Contract.Host
---@field PROTOCOL integer
---@field max_line_bytes fun(): integer                     # `api.MAX_REQUEST_BYTES` plus the id and the method; read at call time.
---@field handle fun(line: string): string|nil              # One request line -> `<id>\t<document>`, or nil when it is no request.
---@field serve fun(input: file*, output: file*, warn?: fun(text: string))

return {}
