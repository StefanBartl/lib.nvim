---@module 'lib.vim.require'
--- Classic-Vim-Spiegelung von `lib.nvim.require`.
--- STATUS: Platzhalter (noch nicht portiert) — siehe doc/vim-parity.md.
--- Die öffentliche API ist über `__index` gespiegelt; ein Funktionsaufruf
--- wirft einen klaren not-implemented-Fehler. Echte Implementierung hier
--- einsetzen, sobald nach klassischem Vim portiert.
return require("lib.vim._stub")("require")
