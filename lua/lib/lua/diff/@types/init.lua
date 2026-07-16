---@meta
---@module 'lib.lua.diff.@types'

---1-based, inclusive. Replacing `a[start..a_end]` with `b[start..b_end]`
---turns `a` into `b`. `a_end = start - 1` means a pure insertion;
---`b_end = start - 1` means a pure deletion.
---@class LibDiffSpliceRegion
---@field start integer
---@field a_end integer
---@field b_end integer

---@alias LibDiffOpKind "equal"|"insert"|"delete"

---@class LibDiffOp
---@field op LibDiffOpKind
---@field value string

---@class LibDiffLines
---@field diff fun(a: string[], b: string[]): LibDiffSpliceRegion|nil

---@class LibDiffMyers
---@field diff fun(a: string[], b: string[]): LibDiffOp[]

---@class LibDiff
---@field lines LibDiffLines
---@field myers LibDiffMyers
