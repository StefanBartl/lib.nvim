---@meta
---@module 'lib.nvim.contract.ops.@types'

---One field type of an operation.
---@class Lib.Contract.OpsType
---@field is fun(value: any): boolean
---@field label string             # How a refusal names it: "<field> must be <label>".

---One operation of a contract.
---@class Lib.Contract.OpsOperation
---@field fields table<string, string>                  # Field name -> type (`string`, `object`, `strings`, `integer`, `boolean`, or one of `cfg.types`). A field that is not listed is refused.
---@field run fun(op: table, ctx: table): table         # The handler: answers the entry (`ok`, `outcome`, ...). `ctx.dry` says dry run.

---@class Lib.Contract.OpsConfig
---@field doc Lib.Contract.Doc                          # The document builder (`lib.nvim.contract.doc`).
---@field ops table<string, Lib.Contract.OpsOperation>
---@field order? string[]                               # The order the messages name the operations in (default: byte order of the names).
---@field context? fun(params: table, opts: table): table|nil, Lib.Contract.Error|string|nil  # Builds `ctx` (it needs `root`); `nil, err` refuses the request (`run` answers it as an error of the contract: a text is classified, the root hidden). Default `{ root = opts.root }`.
---@field finish? fun(ctx: table, results: table[])     # Runs once after the last operation (also on a dry run: look at `ctx.dry`). May change the entries; `ok` of the document is judged after it.
---@field types? table<string, Lib.Contract.OpsType>    # The plugin's own field types.
---@field limits? { batch_ops?: integer, client_op_id?: integer }  # Default 100 operations, 64 characters.
---@field patterns? Lib.Contract.ErrorPattern[]         # The plugin's own error-message patterns (`failure`).

---@class Lib.Contract.Ops
---@field OPS string[]
---@field limits { batch_ops: integer, client_op_id: integer }
---@field failure fun(root: string|nil, err: any, info?: table): table
---@field refuse fun(code: string, message: string, details?: table): table
---@field check_shape fun(params: any): Lib.Contract.Error|nil
---@field run fun(params: table, opts?: table): table|nil, Lib.Contract.Error|nil  # The sealed `<prefix>.result` (its `results` are remembered: do not change them), or an error of the contract.
---@field method fun(): Lib.Contract.ApiMethod

return {}
