---@meta
---@module 'lib.nvim.fs.@types.path'

--- CDX: `Lib.Fs.Path` used to be declared here as part of the fictional
--- CDX: `Lib.Fs` grouping (see `init.lua`'s note). It's real — `fs.path`
--- CDX: genuinely returns this shape — so the definition now lives at its
--- CDX: actual module, `lib/nvim/fs/path/@types/init.lua`, next to the
--- CDX: `---@type Lib.Fs.Path` annotation that uses it. This file is left
--- CDX: empty rather than deleted, since `init.lua`'s (also fictional,
--- CDX: per its own note) `Lib.Fs` class still has a `path` field pointing
--- CDX: at the class name.

return {}
