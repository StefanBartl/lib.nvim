# Beispiel - Setup

## Table of content

  - [Grundidee](#grundidee)
  - [Unterschiedliche Verwendung: Marksman vs LuaLS](#unterschiedliche-verwendung-marksman-vs-luals)
    - [1. Marksman (Markdown)](#1-marksman-markdown)
    - [2. LuaLS (Lua)](#2-luals-lua)
  - [Zusammenfassung der Unterschiede](#zusammenfassung-der-unterschiede)
    - [Best Practice](#best-practice)

---

Hier ist eine detaillierte Erklärung, wie man dein `polymorphic_root_resolver`-Modul sinnvoll in **Marksman** und **LuaLS** verwendet, inklusive der Unterschiede im Setup:

---

## Grundidee

Dein Modul `lib.nvim.fs.polymorphic_root_resolver` liefert eine **funktionale, polymorphe Root-Ermittlung**:

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")
local resolve_root = resolver_module.make_root_dir_resolver()
```

* `resolve_root(arg, cb?)` akzeptiert entweder:

  * `arg` = **Buffer-Nummer** → liest automatisch den Dateinamen des Buffers
  * `arg` = **Dateipfad** → benutzt ihn direkt
* Optionaler Callback `cb(root)` ermöglicht Integration in **asynchrone Pipelines**, wie sie bei Neovims native LSP-Konfiguration nötig ist.

---

## Unterschiedliche Verwendung: Marksman vs LuaLS

### 1. Marksman (Markdown)

* **Merkmal:** Markdown-Projekte haben oft `.marksman.toml`, `mkdocs.yml` oder `.git` als Root-Indikatoren.
* **Setup:** Root-Resolver muss **polymorph** sein, um sowohl `bufnr` als auch `fname` zu unterstützen, da Neovims neue LSP-API (`vim.lsp.enable`) Buffer-Nummern übergibt.
* **Beispiel:**

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")

local resolve_root = resolver_module.make_root_dir_resolver({
  markers = { ".marksman.toml", ".git", "mkdocs.yml" },
  include_stdpath_config = false,
})

vim.lsp.config("marksman", {
  cmd = { "marksman", "server" },
  filetypes = { "markdown", "markdown.mdx" },
  root_dir = resolve_root,  -- polymorpher Resolver
  single_file_support = false,
})
```

* **Warum hier wichtig:** Markdown-Projekte haben oft mehrere kleine Dokumente. Root muss zuverlässig identifiziert werden, sonst behandelt der LSP jede Datei als isoliert → fehlende Linkauflösung und fehlerhafte Workspace-Diagnostik.

---

### 2. LuaLS (Lua)

* **Merkmal:** Lua-Projekte nutzen `.luarc.json`, `.neoconf.json`, `selene.toml`, `stylua.toml` und VCS-Markierungen.
* **Setup:** Root-Resolver kann **ebenfalls polymorph** sein, da LuaLS auch `bufnr` oder `fname` akzeptiert.
* **Optional:** Du könntest für LuaLS die Konfiguration etwas strenger machen und zusätzlich `include_stdpath_config = true` setzen, damit Skripte in der Neovim-Konfigurationsstruktur automatisch als Root erkannt werden.
* **Beispiel:**

```lua
local resolver_module = require("lib.nvim.fs.polymorphic_root_resolver")

local resolve_root = resolver_module.make_root_dir_resolver({
  markers = { ".git", ".hg", ".svn", ".luarc.json", ".neoconf.json", "selene.toml", "stylua.toml" },
  include_stdpath_config = true,
})

vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_dir = resolve_root,
  single_file_support = true,
})
```

* **Warum hier wichtig:** LuaLS verwendet Root-Dir, um Workspace-Libraries (`library`) korrekt zu laden und Diagnosen nur innerhalb des Projekts zu prüfen.

---

## Zusammenfassung der Unterschiede

| Eigenschaft         | Marksman                               | LuaLS                                       |
| ------------------- | -------------------------------------- | ------------------------------------------- |
| Typische Marker     | `.marksman.toml`, `mkdocs.yml`, `.git` | `.git`, `.luarc.json`, `.neoconf.json` usw. |
| Fallback Stdpath    | selten notwendig (nicht config)        | optional sinnvoll (Neovim config)           |
| Single-File Support | false                                  | true                                        |
| Fokus               | Projektweite Markdown-Link-Auflösung   | Workspace-Libraries & Projekt-Diagnostik    |
| Wichtigkeit Root    | hoch für korrekte Linkprüfungen        | hoch für Workspace / Diagnosen / Preload    |

---

### Best Practice

1. **Polymorpher Resolver für beide:** sowohl `bufnr` als auch `fname` abdecken.
2. **Marksman:** Marker an Markdown-spezifische Dateien anpassen, Stdpath-Config ausschalten.
3. **LuaLS:** Marker erweitern auf Lua-Projektdateien, Stdpath-Config optional einschalten.
4. **Callback nutzen:** immer mit LSP-Pipelines kompatibel.
5. **Shared Funktion:** Das gleiche Modul kann für beide LSPs wiederverwendet werden → DRY-Prinzip.

---

