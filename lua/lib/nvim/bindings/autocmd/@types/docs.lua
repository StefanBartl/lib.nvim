---@meta
---@module 'lib.nvim.bindings.autocmd.@types.docs'

--- Every field is optional; see `defaults()` for what each is inferred from.
--- Pass one only where the guess would be wrong -- a repo with several plugins
--- under `lua/`, say, or a note recording which configuration was used.
---@class Lib.Autocmd.Docs.Opts
---@field dir? string         # Target directory. Default: `<root>/lua/<plugin>/bindings/autocmd`.
---@field filter? fun(record: Lib.Autocmd.Record): boolean  # Default: every record created from a file inside `root`.
---@field root? string        # Repo root. Default: derived from the caller's own source path, else cwd.
---@field note? string        # An extra paragraph for the header, e.g. which config produced this.
---@field unregistered? integer # Direct `nvim_create_autocmd` call sites in the repo; rendered as a warning. Counted automatically when `root` is known.

---@class Lib.Autocmd.Docs.AllOpts
---@field under? string   # Only repositories inside this directory. Without it, every repo that registered anything -- including plugins you did not write.
---@field note? string    # Passed through to every repo's header.
---@field dry_run? boolean # Report what would be written, write nothing.

---@class Lib.Autocmd.Docs.AllResult
---@field root string
---@field plugin string
---@field dir string
---@field written string[]
---@field records integer
---@field unregistered integer
---@field err string|nil

---`require("lib.nvim.bindings.autocmd.docs")` itself: generated
---`bindings/autocmd/` markdown writers.
---@class Lib.Autocmd.Docs
---@field write fun(opts?: Lib.Autocmd.Docs.Opts): (ok: boolean, err: string|nil, written: string[])
---@field check fun(opts?: Lib.Autocmd.Docs.Opts): (up_to_date: boolean, stale: string[])
---@field write_all fun(opts?: Lib.Autocmd.Docs.AllOpts): Lib.Autocmd.Docs.AllResult[]
---@field create_usercmd fun(name?: string): nil

return {}
