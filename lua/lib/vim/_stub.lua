---@module 'lib.vim._stub'
--- Erzeugt einen API-kompatiblen Platzhalter für ein `lib.nvim`-Modul, das noch
--- nicht nach klassischem Vim portiert wurde.
---
--- Die Spiegelung etabliert die API-Oberfläche (jeder Funktionsname ist
--- zugreifbar), wirft aber bei tatsächlichem Aufruf einen aussagekräftigen
--- Fehler. So können abhängige Plugins gegen `lib.vim.*` programmieren, während
--- die echten Vim-Implementierungen nach und nach ergänzt werden.
---
--- Verwendung in einem noch nicht portierten Modul `lib/vim/<modul>/init.lua`:
---   return require("lib.vim._stub")("<modul>")

---@param modname string Name des gespiegelten lib.nvim-Moduls (z.B. "notify")
---@return table
return function(modname)
  return setmetatable({}, {
    __index = function(_, key)
      return function()
        error(
          string.format(
            "lib.vim.%s.%s: noch nicht für klassisches Vim implementiert. "
              .. "Unter Neovim stattdessen lib.nvim.%s verwenden.",
            modname,
            tostring(key),
            modname
          ),
          2
        )
      end
    end,
  })
end
