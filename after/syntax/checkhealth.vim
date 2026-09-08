" Neovim's own checkhealth syntax ($VIMRUNTIME/syntax/checkhealth.vim)
" defines exactly three keywords: ERROR, WARNING, OK. There is no INFO --
" core never writes one, since vim.health.info() emits no tag at all. Several
" plugins in this ecosystem (filetree.nvim, pickers.nvim, ...) hand-write an
" "ℹ️ INFO " prefix in status lists (adapter/backend/engine) that need the
" same kind of highlight; DiagnosticInfo is a standard group every
" colorscheme already sets.
"
" Lives here rather than in each plugin's own repo or in a personal config:
" every one of those plugins already depends on lib.nvim, so shipping it once
" here means it works for every consumer automatically -- not just the
" plugin author's own setup. See docs/health.md.
syn keyword DiagnosticInfo INFO
