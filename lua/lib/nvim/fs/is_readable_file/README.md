Despite the name, this does not only check files: it returns `true` when
`filepath` is either a readable file (`vim.fn.filereadable`) or an existing
directory (`vim.fn.isdirectory`), and `false` only when neither is the case
(e.g. the path doesn't exist, or exists but isn't readable). Callers that need
"readable file, not a directory" should add their own `is_dir` check —
`lib.nvim.fs.is_dir` — on top of this.
