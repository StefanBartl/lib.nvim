---@module 'lib.vim'
--- Namespace-Aggregator für die Spiegelung nach klassischem Vim.
---
--- Ziel: für jedes Modul aus `lib.nvim.*` ein API-gleiches Pendant in
--- `lib.vim.*`. Wo eine Portierung auf `vim.fn`/Vimscript machbar ist, gibt es
--- eine echte Implementierung; andernfalls liefert das Modul einen Platzhalter
--- mit identischer Signatur (siehe `lib.vim._stub`), der bei Aufruf einen
--- klaren `not-implemented`-Fehler wirft.
---
---   local Vim = require("lib.vim")
---   Vim.notify    -- == require("lib.vim.notify")
---
--- Portierungsstatus: doc/vim-parity.md

local cache = {}

return setmetatable({}, {
  __index = function(_, key)
    if cache[key] == nil then
      cache[key] = require("lib.vim." .. key)
    end
    return cache[key]
  end,
})
