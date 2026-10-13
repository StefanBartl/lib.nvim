---@meta
---@module 'lib.nvim.contract.api.@types'

---One method of a contract.
---@class Lib.Contract.ApiMethod
---@field params table<string, string>   Parameter name -> its type (`string`, `integer`, `boolean`, `number`, `object`, `string_list`, `object_list`, or one of `cfg.types`).
---@field flat? boolean                  The parameters are the request's own fields (a write door), not under `params`.
---@field keep_null? boolean             A JSON `null` stays `vim.NIL` (it means "remove" in a patch) instead of being absent.
---@field required? string[]             Parameters that must be given: otherwise `invalid_argument` ("<method> needs the parameter <name>").
---@field run fun(params: table, opts: table): table|nil, Lib.Contract.Error|string|nil

---@class Lib.Contract.ApiConfig
---@field doc Lib.Contract.Doc                                      The document builder (`lib.nvim.contract.doc`).
---@field methods table<string, Lib.Contract.ApiMethod>
---@field engine_opts? string[]                                     Keys of `call`'s opts handed to `run` (default `{ "root" }`).
---@field root_of? fun(engine_opts: table, opts: table): string|nil  The root to hide in an error message (default `engine_opts.root`). The plugin resolves it the way its engine does.
---@field patterns? Lib.Contract.ErrorPattern[]                     The plugin's own error-message patterns (`contract.errors`).
---@field types? table<string, fun(value: any): boolean>            The plugin's own parameter types.
---@field max_request_bytes? integer                                Default 256 KiB.

---@class Lib.Contract.Api
---@field METHODS table<string, Lib.Contract.ApiMethod>
---@field MAX_REQUEST_BYTES integer                                 Read at call time.
---@field methods fun(): string[]
---@field minimal_error fun(code: string, message: string): string
---@field call fun(name: string, request?: string|table, opts?: table): string, string|nil

return {}
