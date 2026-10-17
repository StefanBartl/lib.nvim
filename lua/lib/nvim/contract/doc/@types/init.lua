---@meta
---@module 'lib.nvim.contract.doc.@types'

---Every key is checked where `doc.new` is called; a wrong one raises with the position of the caller.
---@class Lib.Contract.DocConfig
---@field plugin string            The plugin named in every head, e.g. `tasks.nvim`.
---@field schema integer           The version of the contract (`schema` of every document), a whole number from 1.
---@field kind_prefix? string      Prefix of the document kinds (`tasks` gives `tasks.hello`), non-empty. Default: the plugin without `.nvim`.
---@field scope_key? string        Name of the head field that names the source (`{ id = <basename of the root> }`), non-empty and no field of the documents themselves (`engine`, `kind`, `code`, ...). Default `vault`.
---@field placeholder? string      What `redact` writes for the root, non-empty. Default `<scope_key>`, e.g. `<vault>`.
---@field engine_version? string   The engine's own version (not the contract's). Default `0.0.0`.
---@field plugin_root? string      The plugin's checkout, non-empty, for the commit named in `engine.git`. Without it the commit is `unknown` and git is never started.
---@field max_bytes? integer       Largest document, a whole number from 1 (default 8 MiB).
---@field too_large_hint? string   What the `payload_too_large` message advises (default `ask for a page or an area`).
---@field prewarm? boolean         `true` calls `prewarm()` in `new`: the git lookup of `engine.git` starts in the background.

---@class Lib.Contract.Doc
---@field SCHEMA integer
---@field PLUGIN string
---@field ENGINE_VERSION string
---@field MAX_DOC_BYTES integer                                   Seam: read at call time.
---@field ERROR_KIND string                                       `<prefix>.error`
---@field PLACEHOLDER string
---@field kind fun(name: string): string
---@field clock fun(): string                                     Seam: `generated_at`.
---@field engine_info fun(): { version: string, git: string, nvim: string }  Seam: `engine`.
---@field prewarm fun()                                           Start the git lookup in the background; until it calls back `engine.git` is `unknown` (not cached, no wait).
---@field head fun(kind: string, root?: string): table                       `root` may be spelled with either slash and a trailing slash.
---@field relative fun(root: string, path: string): string|nil                `root` as for `head`; `""` is no root: nothing is inside it.
---@field safe_path fun(root: string, s: string): string
---@field redact fun(root: string, s: string): string                         `root` as for `head`; `""` and `/` hide nothing.
---@field rev_of fun(lines: string[]): string
---@field seal fun(doc: table, rev?: string): table                          Raises for a value JSON cannot hold (the document is left as it was).
---@field encode fun(doc: table, opts?: Lib.Json.CanonicalOpts): string|nil, Lib.Contract.Error|nil
---@field error_doc fun(err: Lib.Contract.Error|any, root?: string): table   A malformed `err` is coerced, never a throw.

return {}
