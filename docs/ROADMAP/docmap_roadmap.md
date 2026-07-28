# Implementierungs-Konzept: `lib.nvim.docmap` — Graph-Views & Browser-UI

> Modul: `lua/lib/nvim/docmap/`. Output: `docs/map/index.html`, `overview.md`,
> `module_map.json`. Vorbild: Doxygen (Collaboration / Include / Caller /
> Callee Graphs).
>
> **Verschoben aus der nvim-Config-Roadmap** (2026-07-28): lebte vorher unter
> `docs/ROADMAP/personal/lib_nvim/docmodule.md` in der separaten nvim-Config,
> obwohl das Modul selbst vollständig in diesem Repo (`lib.nvim`) liegt —
> Datei jetzt hier, unter dem korrekten Modulnamen (`docmap`, nicht
> `docmodule` — das war schon vorher nur ein Roadmap-Dateiname, nie der
> Code-Name). Fortsetzung in [`docmap_roadmap_next.md`](docmap_roadmap_next.md).
> Historischer Vorläufer dieser Datei: [`module_map.md`](module_map.md) (das
> ursprüngliche Konzept, bevor die Graph-Views gebaut wurden) und
> [`docmap_hierarchy_and_integrations.md`](docmap_hierarchy_and_integrations.md)
> (Zwischenkonzept für Hierarchy-Tab/LuaLS/`install()`/mdview — inzwischen
> größtenteils durch die Phasen unten überholt/umgesetzt, siehe dort für die
> ursprüngliche Analyse).

## STATUS: umgesetzt (Phasen A–G)

Branch `claude/lib-nvim-docmodule-roadmap-ed6eab`. Alles unten Beschriebene ist
implementiert; `--check` grün, Artefakte byte-deterministisch, 0 errors.
Zahlen aus dem echten Lauf über lib.nvim: **387 require-Kanten, 611 call-Kanten,
330 type-Kanten** (letztere nur mit `--full`).

| Phase | Status | Wo |
|---|---|---|
| A — Require-Graph | ✅ | `deps.lua`, neue Checks in `check.lua` |
| B — Call-Graph | ✅ | `calls.lua`, Parse-Reuse in `functions.lua` |
| C — Views Deps/Calls + Richtung/Tiefe | ✅ | `render/html.lua` |
| D — Funktions-Ids + State-Achsen | ✅ | `render/html.lua` |
| E — Kontextmenü | ✅ | `render/html.lua` |
| F — Bewegung (keyed reconcile) | ✅ | `render/html.lua` |
| G — Ausbau | ✅ | Mermaid-Deps, `:LibMap graph`, Handle-API, SVG-Export |

### Abweichungen vom Konzept — und warum

1. **Deferred-Requires unterscheiden** (nicht im Konzept). Der Zyklus-Check
   meldete zunächst 6 Zyklen — *jeder einzelne* war ein absichtlicher Lazy-Load
   (`require()` im Funktionsrumpf). Ein Check, der nur auf Absicht anspringt,
   wird weggeklickt und kostet dann die echten mit. `RawRequire.deferred` wird
   aus dem Parse bestimmt (**jeder** Funktionsrumpf, nicht nur Top-Level — der
   Rest-Zyklus steckte in einem anonymen `__index = function(_, k)`), der
   Check sieht nur Load-Time-Kanten. Beide Arten bleiben echte Kanten im
   Deps-View, lazy gepunktet.
2. **Kommentarzeilen überspringen** (nicht im Konzept). Die vier
   verbleibenden „Zyklen" waren `require`-Aufrufe in **Doc-Kommentaren**
   (`---   local kit = require("lib.nvim.ui.kit")`) — davon ist der Baum voll.
   Nach dem Fix: 0 Zyklen.
3. **`deps`/`calls` laufen in `scan()`**, nicht in `scan_full()`. Sie brauchen
   kein externes Tool; so sieht jeder `scan()`-Aufrufer dieselbe fertige IR.
4. **Kanten-Sortierung pro Produzent**, nicht global. Ein gemeinsamer
   Comparator müsste jede Kind-Variante kennen — `luals.lua` verglich sonst
   `from_class` gegen `nil`, sobald die erste require-Kante da war.
5. **Kanten-Interpolation verworfen** (Konzept-Variante 2 gewählt): Kanten
   werden während der Box-Bewegung ausgeblendet und danach eingeblendet.
6. **Funktionen im Tree** hängen hinter einer eigenen, eingeklappten
   `ƒ N functions`-Gruppe statt in `children` — der Baum rendert eager, ~1500
   zusätzliche Zeilen im Default-Zustand hätten die Struktur begraben.

### Fallstricke, die beim Umsetzen aufgetaucht sind

- **`]]` beendet den Lua-Long-String.** Das gesamte JS liegt in `[[ … ]]`.
  Ein Array von Arrays (`[['a','b'],['c','d']]`) endet auf `]]` und macht den
  Rest der Datei zu Lua-Quelltext. Betraf erst die Legende, dann den Kommentar,
  der davor warnte. Im Renderer nie zwei schließende eckige Klammern
  nebeneinander.
- **Search-Preview vs. zentrierte Funktion.** Live-Tippen re-zentriert ohne den
  Rest des States anzufassen; ohne Guard hätte der Calls-View weiter die alte
  Funktion gezeichnet. Gelöst über „`state.fn` gilt nur, solange das Zentrum
  ihr eigener Node ist".
- **Backedges brauchen echtes Routing.** Bestätigt: mit der alten S-Kurve
  laufen sie durch die Boxen. Jetzt seitlich raus/rein, plus Pfeilköpfe.

### Debug-Runde nach dem ersten Commit (`965ba60`)

Alle vier durch *Benutzen* des ausgelieferten Artefakts gefunden, keiner durch
Lesen des Codes:

1. **Empty-State-Meldung blieb stehen.** `reconcile()` entfernt nur Boxen, die
   es kennt — der `<p class="hmsg">` aus dem leeren Zweig überlebte in die
   nächste Zeichnung. Calls-auf-Namespace (leer) → Modules zeigte
   „lib.nvim declares no functions." über 90 Boxen.
2. **Hover-Fokus löste nie aus.** `mouseleave` feuert erst beim Verlassen von
   `#hgraph`; neben einer Box im Leerraum blieb das ganze Diagramm gedimmt.
3. **`:LibMap graph` öffnete nichts.** Fragment an einen *Dateipfad* gehängt →
   `explorer.exe`/`xdg-open` sucht eine Datei namens `index.html#tab=…`. Jetzt
   `file://`-URL; `:LibMap open` bleibt ein Pfad.
4. **`:LibMap graph deps lib.nvim.fs` fand nichts.** Das Verzeichnis ist eine
   *Namespace* ohne `init.lua`, hat also kein `@module`. Namen lösen jetzt auch
   über den pfad-implizierten Modulnamen auf (`check.expected_module`
   exportiert statt einer zweiten Kopie der Ableitung).

Plus: Twisty der Funktions-Gruppe blieb nach „Collapse" auf ▾.

### Nachträglich getestet (`a33b7b5`)

`opts.layers`, `opts.calls_heuristic` und die Handle-Queries waren ausgeliefert
und noch nie gelaufen. Alle drei verhalten sich korrekt — insbesondere lässt die
Heuristik einen von zwei Modulen deklarierten Namen fallen, statt zu raten. Als
Specs abgesichert, weil genau dieser Fall in einem Happy-Path-Test fehlt.

### Nebenbefund: CI war seit ~8 Commits rot (`b266353`)

Nicht durch diese Arbeit verursacht. `leafo/gh-actions-lua@v10` bekommt das
LuaJIT-2.1-Tarball nicht mehr (404) — der `luacheck`-Job scheiterte im
*Setup*, luacheck lief also seit Wochen überhaupt nicht, auch nicht über die
neuen Dateien. Auf PUC Lua 5.4 umgestellt; `std = "luajit"` in `.luacheckrc`
bleibt und ist unabhängig davon, welcher Interpreter luacheck ausführt.
CI ist jetzt grün.

---

## 0. Ist-Stand (was schon da ist)

| Baustein | Datei | Status |
|---|---|---|
| Header-Scan (`@module`, Summary, README, Types) | `scan.lua` | ✅ |
| Funktions-Scan via treesitter (`@param`/`@return`/`@see`/…) | `functions.lua` | ✅ **Deklarationen**, keine Call-Sites |
| LuaLS-Enrichment: `@class`/`@alias` + Typ-Kanten | `luals.lua` | ✅ opt-in (`:LibMap full`) |
| Drift-Checks | `check.lua` | ✅ |
| HTML: Tab **Tree** (Baum + Detail-Pane) | `render/html.lua` | ✅ |
| HTML: Tab **Hierarchy**, Views **Modules** / **Types** | `render/html.lua` | ✅ |
| History-State `{tab, id, center, view}` | `render/html.lua` | ✅ |

**Fehlt gegenüber der Vision:**

1. **Keine Require-Kanten im IR.** `check_orphans` sammelt `require("…")`-Strings
   *transient* innerhalb des Checks und wirft sie weg. Es gibt also kein
   Abhängigkeits-Graph-Datum, das ein Renderer lesen könnte.
2. **Keine Call-Kanten.** `functions.lua` findet Funktions-*Definitionen*, nie
   Aufrufe. Damit gibt es weder Callee- noch Caller-Graph.
3. **Kein Kontextmenü.** Navigation nur über Linksklick / Doppelklick / den
   `Hierarchy ↳`-Link im Detail-Pane.
4. **Keine Bewegung.** `drawHierarchy()` macht `hgraph.innerHTML = ""` und baut
   alles neu — jeder Wechsel ist ein harter Schnitt.
5. **Funktionen sind keine navigierbaren Objekte.** Sie existieren nur als
   Text-Abschnitt im Detail-Pane; man kann nicht auf `M.scan_full` zentrieren.

Das Konzept unten schließt genau diese fünf Lücken, in dieser Reihenfolge —
Daten zuerst, UI danach, Animation zuletzt.

---

## 1. Datenmodell: Kanten bekommen eine `kind`

Heute ist `ir.edges` implizit „Typ-Referenzkanten". Das wird verallgemeinert;
**ein** Kanten-Array mit Diskriminator statt drei parallelen Feldern, damit
Layout/Filter/Zeichnen genau einmal existieren.

```lua
---@alias Lib.Docmap.EdgeKind
---| "type"    # Feld einer @class referenziert eine andere @class (heute: ir.edges)
---| "require" # Datei A enthält require("modul.b")
---| "call"    # Funktion A ruft Funktion B auf

---@class Lib.Docmap.Edge
---@field kind Lib.Docmap.EdgeKind
---@field from string          Node-Id (Quelle)
---@field to string            Node-Id (Ziel)
---@field from_class string?   nur kind="type"
---@field to_class string?     nur kind="type"
---@field via string?          kind="type": Feldname
---@field from_fn string?      nur kind="call": qualifizierter Name, z.B. "M.scan_full"
---@field to_fn string?        nur kind="call"
---@field to_module string?    nur kind="require": deklarierter require-String
---@field line integer?        Zeile der Call-Site / des require
---@field confidence ("exact"|"heuristic")?  nur kind="call", s. §3
```

**Migrationsregel:** bestehende Typ-Kanten bekommen `kind = "type"`, sonst
unverändert. `luals.lua` bleibt der einzige Produzent davon. Renderer, die heute
`IR.edges` roh iterieren (Types-View, `layoutTypes`), filtern künftig auf
`kind === "type"`. **IR-Schema-Version (`meta.schema`) hochzählen.**

Zusätzlich pro Node, als bequemer Index (aus den Kanten abgeleitet, nicht
zusätzliche Wahrheit):

```lua
---@field requires string[]     Node-Ids, die dieser Node requiret
---@field required_by string[]  Node-Ids, die diesen Node requiren
```

---

## 2. Phase A — Require-Graph (`deps.lua`)

Neue Stage zwischen `scan` und `check`, unconditional (kein LuaLS nötig, kostet
nur das Lesen von Dateien, die `scan` sowieso schon anfasst).

- **Extraktion:** dasselbe Pattern wie heute in `check_orphans`
  (`require%s*%(?%s*['\"]([%w%._%-]+)['\"]`), aber *pro Datei attribuiert*
  statt in ein globales Set geworfen. Zeilennummer mitnehmen.
- **Auflösung:** `module`-String → Node-Id über eine `module → id`-Map aus
  `ir.order`. Nicht auflösbare Requires (`vim.*`, externe Plugins) werden
  **verworfen**, nicht als Fremd-Node erfunden — der Graph bleibt „was in diesem
  Baum liegt". (Optional später: Toolbar-Schalter „externe Requires zeigen",
  dann als eigene Box-Klasse `k-external`.)
- **Dedupe:** mehrfaches `require` desselben Moduls in einer Datei = eine Kante.
- **`check_orphans` baut auf `ir.edges` auf** statt selbst zu scannen — die
  Datei-I/O passiert danach genau einmal.

**Neue Checks, die dadurch fast gratis werden:**

| Check | Severity | Fängt |
|---|---|---|
| `require-cycle` | warn | Zyklus im Require-Graph (Tarjan SCC > 1). |
| `require-not-declared` | info | Kante existiert, aber Ziel-Modul hat kein `@module`. |
| `layer-violation` | warn | opt-in via `opts.layers`: `lib.vim.*` darf nicht `lib.nvim.*` requiren o.ä. |

`layer-violation` ist optional und repo-spezifisch (`extra_checks`), nicht
generisch — aber das Datum dafür liegt ab hier bereit.

**Acceptance:** `module_map.json` enthält `kind:"require"`-Kanten; Anzahl
deckt sich mit einem manuellen `grep -c require` über `lua/` (± unaufgelöste);
`--check` bleibt byte-deterministisch (Kanten **sortiert** ausgeben:
`from, to, from_fn, to_fn, line`).

---

## 3. Phase B — Call-Graph (`calls.lua`)

Der ehrlich schwierigste Teil. Kein LuaLS (siehe README: `--doc` sieht die
meisten Funktionen dieses Repos gar nicht), also **treesitter**, wie schon in
`functions.lua`.

### Vorgehen pro Datei

1. **Alias-Tabelle bauen:** `local fs = require("lib.nvim.fs")` →
   `fs → lib.nvim.fs`. Auch `local x = require("…").sub` und
   `local M = require("…")` erfassen. Das ist der Schlüssel: ohne Alias-Auflösung
   ist ein Call-Graph in Lua Kaffeesatz.
2. **Enclosing-Function bestimmen:** über die schon in `functions.lua`
   ermittelten Definitions-Ranges — welche Top-Level-Funktion enthält die
   Call-Site (Zeilenintervall)? Damit hat die Kante ein `from_fn`.
3. **Call-Sites finden:** treesitter-Query auf `function_call` mit
   `method_index_expression` / `dot_index_expression`. Drei Formen:
   - `fs.read(x)` → Alias `fs` auflöst → Node + `to_fn = "M.read"` (`confidence: "exact"`)
   - `M.helper(x)` / `helper(x)` → modul-intern, Ziel im selben Node
     (`confidence: "exact"`)
   - `obj:method()` auf einem nicht auflösbaren Empfänger → **verwerfen**,
     nicht raten.
4. **Fallback-Heuristik (opt-in, `opts.calls_heuristic`):** unaufgelöster
   Bezeichner, dessen Name genau einer Funktion im Baum eindeutig entspricht →
   Kante mit `confidence: "heuristic"`, im UI gestrichelt/blasser gezeichnet.
   Default: **aus**. Ein falscher Call-Graph ist schlimmer als ein
   unvollständiger.

### Grenzen — explizit dokumentieren, nicht kaschieren

- Dynamik (`M[name]()`, Callbacks über Tabellen, `vim.schedule(fn)`) wird nicht
  erfasst. Doxygen kann das für C++ auch nicht.
- `lib.nvim.require`'s Lazy/Metatable-Strategien (`strategies/`) erzeugen
  Aufrufe, die syntaktisch nirgends stehen. Im UI als Hinweis-Badge am Node
  („dynamic dispatch — call graph incomplete").
- Deswegen: Call-Kanten sind **nie** Grundlage eines `error`-Checks.

**Performance:** treesitter-Parse pro Datei passiert in `functions.lua` bereits.
`calls.lua` muss denselben Tree wiederverwenden → `functions.lua` gibt den
geparsten Tree zurück bzw. beide Scans laufen in einem Durchgang
(`functions.scan_file` → `{ functions, calls }`). Sonst verdoppeln sich die
Scan-Kosten für nichts.

**Acceptance:** für `lib.nvim.docmap` selbst zeigt der Callee-Graph von
`init.generate` mindestens `scan`, `check`, `render.html`, `json.encode`;
Caller-Graph von `json.encode` zeigt `init.generate`. Manuell verifizierbar.

---

## 4. Phase C — Views: vier statt zwei

Die Hierarchy-Toolbar bekommt vier Buttons (`data-view`), Doxygen-Analogie in
Klammern:

| View | Boxen | Kanten | Doxygen-Pendant |
|---|---|---|---|
| **Modules** | IR-Nodes | `children` (solid) | Directory / Class Hierarchy |
| **Types** | `@class`/`@alias` | `kind="type"` | Collaboration Diagram |
| **Deps** *(neu)* | IR-Nodes | `kind="require"` | Include Dependency Graph |
| **Calls** *(neu)* | einzelne **Funktionen** | `kind="call"` | Caller / Callee Graph |

### Richtung als eigene Achse (`dir`)

Für **Deps** und **Calls** ist die Richtung eine zweite Dimension, kein weiterer
View. Toolbar: `[ ← Eingehend | ⇄ Beides | Ausgehend → ]`

- `out` — was das Objekt braucht / aufruft (Callee).
- `in` — wer es braucht / aufruft (Caller) → Kanten **umgedreht** durchlaufen.
- `both` — bidirektional, zentriertes Objekt in der Mittellage, Caller darüber,
  Callee darunter (das ist der Doxygen-Look).

### Tiefe (`depth`)

Slider / `[1] [2] [3] [∞]` in der Toolbar. Default **2**. `MAX_HNODES` (90)
bleibt als harte Obergrenze bestehen — bei Require-Graphen explodiert die
Nachbarschaft deutlich schneller als bei einem Baum. Bei Abschneidung: die
bestehende `.htrunc`-Notiz, plus „+N weitere" als klickbarer Rand-Chip am
letzten Layer.

### Layout bei Zyklen

`layoutModules` ist eine BFS über einen **Baum**. Require-/Call-Graphen sind
gerichtete Graphen **mit** Zyklen. Die vorhandene BFS ist dagegen bereits robust
(`included[id] !== undefined → continue`, erster Besuch gewinnt die Ebene) —
Rückwärtskanten landen also in einer schon gefüllten Ebene und werden als
„Backedge" gezeichnet. Konsequenz für `edgePath()`: Kanten, bei denen
`to.y <= from.y`, brauchen einen seitlich ausholenden Pfad statt der aktuellen
S-Kurve, sonst laufen sie durch die Boxen. Backedges bekommen eine eigene
CSS-Klasse (`.hedge.back`) und einen Pfeilkopf.

**Pfeilköpfe generell:** Modules/Types kommen heute ohne aus. Für gerichtete
Graphen sind sie zwingend — ein `<marker>` im SVG-`<defs>`, je Kantenart
eingefärbt.

### Legende

Fixe Ecke im `#hgraph-wrap`: Kantenart → Farbe/Strichart, Box-Kind → Farbe.
Ohne Legende ist ein vierfarbiger Graph geraten statt gelesen.

---

## 5. Phase D — Funktionen als navigierbare Objekte

Voraussetzung für die Calls-View. Heute hat nur ein Node eine Id.

- **Funktions-Id:** `"<node.id>#<fn.name>"`, z.B.
  `lua/lib/nvim/docmap/init.lua#M.generate`. Stabil, ableitbar, kollisionsfrei.
- **History-State erweitern:** `{tab, id, center, view, dir, depth, fn}`.
  `serializeState`/`parseState`/`applyState` entsprechend — das ist der Ort, an
  dem alle neuen Achsen zusammenlaufen; keine davon darf an `navigate()` vorbei
  gesetzt werden (siehe README-Warnung zu `replaceState`).
- **Detail-Pane:** jede Funktion in der Functions-Section bekommt eine
  Anker-Zeile mit `Calls ↳` / `Callers ↳`, analog zum bestehenden
  `Hierarchy ↳`-Link.
- **Tree-Tab:** Modul-Zeilen bekommen aufklappbare Funktions-Kinder (Twisty wie
  bisher), damit man Funktionen auch im Baum sieht und nicht nur über die
  Detail-Ansicht erreicht.

---

## 6. Phase E — Kontextmenü (Rechtsklick)

Ein einziges Menü-Widget, gefüttert von einem `describeTarget(el)`, das aus
einem angeklickten Element ermittelt: `{ kind: "node"|"class"|"function", id }`.
Registriert auf `contextmenu` an Tree-Zeilen, Hierarchy-Boxen, Funktions-Einträgen
und Typ-Einträgen im Detail-Pane.

**Einträge (kontextabhängig gefiltert):**

```
Zeige Hierarchie          → navigate({tab:"hierarchy", view:"modules", center:id})
Zeige Abhängigkeiten  ▸   → Ausgehend (requires) / Eingehend (required by) / Beides
Zeige Aufrufe         ▸   → Aufgerufene (callees) / Aufrufer (callers) / Beides
Zeige Typen               → view:"types"
──────────
Im Tree auswählen         → navigate({tab:"tree", id})
Quelle öffnen ↗           → srcUrl(node.source) (+ #Lnnn bei Funktionen)
README öffnen             → nur wenn node.readme
──────────
Als Zentrum fixieren      → Pin, s.u.
Pfad kopieren             → navigator.clipboard
Link kopieren             → location.origin+pathname+"#"+serializeState(state)
```

**Umsetzungsdetails:**
- `preventDefault()` nur, wenn das Ziel tatsächlich ein bekanntes Objekt ist —
  sonst normales Browser-Menü. (Text markieren + kopieren muss weiter gehen.)
- Positionierung an Cursor, Clamping an den Viewport-Rand.
- Schließen bei `click`/`Escape`/`scroll`/`resize`; Pfeiltasten + Enter für
  Tastaturbedienung, `aria-role="menu"`.
- Submenüs (`▸`) als einfache verschachtelte `<ul>`, kein Framework.
- **Deaktiviert statt versteckt**, wenn das Datum fehlt: „Zeige Aufrufe (keine
  Call-Daten — mit `:LibMap full` neu generieren)". Genau wie die Types-View
  heute schon eine erklärende Message zeigt statt leer zu bleiben.

---

## 7. Phase F — Bewegung (das „smooth")

Der Kern der Anforderung — und der Grund, warum `drawHierarchy()` umgebaut
werden muss, nicht nur erweitert.

### Prinzip: FLIP mit stabiler Identität

Heute: `hgraph.innerHTML = ""` → alles neu. Stattdessen ein **keyed reconcile**:

1. Boxen werden in einer `Map<key, HTMLElement>` gehalten (`key` = Node-Id /
   Klassenname / Funktions-Id).
2. Beim Neuzeichnen: neues Layout berechnen (unverändert analytisch, siehe
   README — nichts wird aus dem DOM gemessen, das bleibt so).
3. Dann drei Mengen:
   - **enter** — neue Boxen: eingefügt mit `opacity:0; transform:scale(.92)`,
     im nächsten Frame auf Zielwert.
   - **update** — Boxen, die es vorher schon gab: nur `left/top` ändern sich,
     CSS-`transition: left .32s cubic-bezier(.2,.7,.2,1), top .32s …` erledigt
     die Bewegung. **Das ist der Doxygen-Moment**: zentriert man auf ein
     Nachbarmodul, wandern die gemeinsamen Boxen sichtbar an ihre neue Stelle,
     statt dass das Bild springt.
   - **exit** — verschwundene Boxen: auf `opacity:0` fahren, nach `transitionend`
     entfernen.
4. **Kanten:** SVG-Pfade analog gekeyed (`from|to|kind`). Da `d` nicht
   CSS-animierbar ist: `requestAnimationFrame`-Interpolation zwischen altem und
   neuem `d` über dieselbe Dauer, oder — deutlich billiger und optisch fast
   gleichwertig — Kanten während der Bewegung ausblenden und am Ende mit
   `stroke-dashoffset`-Zeichnen einblenden. **Empfehlung: Variante 2** (kein
   Pfad-Interpolator, keine Framerate-Sorgen bei 90 Boxen).

### Weitere Bewegung

- **Auto-Scroll aufs Zentrum** existiert schon → auf `scrollTo({behavior:"smooth"})`
  umstellen, aber nur wenn `prefers-reduced-motion` nicht gesetzt ist.
- **Highlight-Puls** auf der neu zentrierten Box (kurzer Outline-Flash), damit
  klar ist, worauf sich der Graph gerade bezieht.
- **Hover-Fokus:** Maus über einer Box dimmt alle Boxen/Kanten, die nicht ihre
  direkten Nachbarn sind (`.hgraph.focusing .hnode:not(.near){opacity:.28}`) —
  reines CSS über Klassen, keine Neuberechnung. Bei dichten Require-Graphen ist
  das der Unterschied zwischen lesbar und Spinnennetz.
- **`prefers-reduced-motion: reduce`** ⇒ alle Transition-Dauern auf `0s`. Ein
  einziger Media-Query-Block, kein JS-Zweig.

### Nicht-Ziel

Kein Force-Directed-Layout, keine Physik. Layered/analytisch bleibt — es ist
deterministisch, testbar und funktioniert in einem `display:none`-Pane. Bewegung
entsteht durch Interpolation *zwischen* zwei deterministischen Layouts, nicht
durch eine Simulation.

---

## 8. Phase G — Ausbau drumherum

- **Command-Erweiterung:** `:LibMap graph {deps|calls} [modul]` öffnet den
  HTML-View direkt in der passenden View/Zentrierung (Hash mitgeben). Das
  spiegelt die README-Idee eines `:LibMap functions <module>`.
- **Mermaid-Renderer** (`render/mermaid.lua`) um `graph LR` für Deps erweitern,
  damit die Abhängigkeiten auch auf GitHub in `overview.md` sichtbar sind — dort
  gibt es kein JS.
- **Export**: „Als SVG speichern" — der Graph *ist* schon SVG + HTML-Boxen;
  Boxen als `<foreignObject>` serialisieren oder Boxen optional als native
  SVG-`<rect>+<text>` zeichnen.
- **`install()`-Handle**: `handle.callers(fn_id)` / `handle.callees(fn_id)` /
  `handle.requires(id)` als Live-API — dann kann ein Plugin (oder ein
  Telescope-Picker in nvim) den Graph ohne HTML nutzen.
- **Nvim-seitiger View** (später, eigener Scope): dieselben Daten in einem
  `lib.nvim.ui.kit`-Fenster, Tastatur-Navigation statt Maus.

---

## 9. Reihenfolge & Abhängigkeiten

```
A: deps.lua (require-Kanten)          ─┐
B: calls.lua (call-Kanten)            ─┤→ C: Views Deps/Calls ─┐
D: Funktions-Ids + State-Achsen       ─┘                       ├→ F: Animation
                                        E: Kontextmenü ────────┘
                                        G: Ausbau
```

- **A ist der günstigste erste Schritt** (kleiner Diff, sofort sichtbarer
  Mehrwert, macht `check_orphans` gleichzeitig sauberer).
- **F (Animation) bewusst zuletzt** — sie ist eine Umschreibung von
  `drawHierarchy()`; sie vorher zu machen heißt, sie zweimal zu machen.
- **B ist der einzige Schritt mit echtem Forschungsrisiko** (Alias-Auflösung).
  Wenn er sich zieht: C/E/F laufen mit A allein bereits vollständig, die
  Calls-View bleibt so lange die „keine Daten"-Message.

## 10. Risiken

| Risiko | Umgang |
|---|---|
| Call-Graph rät falsch | `confidence`-Feld, Heuristik default aus, nie `error`-Severity |
| Graph-Explosion bei `depth:∞` | `MAX_HNODES` bleibt, Default-Tiefe 2, Truncation sichtbar machen |
| Determinismus bricht (`--check` wird rot) | Kanten sortiert emittieren, keine Zeitstempel, JSON weiter über `json.lua` |
| Scan-Zeit verdoppelt sich | Ein treesitter-Parse pro Datei für `functions` **und** `calls` |
| `history` erneut subtil kaputt | Neue Achsen (`dir`, `depth`, `fn`) **nur** über `navigate()`; Live-Preview weiterhin ohne `replaceState` |
| Zyklen zerlegen das Layer-Layout | Backedge-Erkennung + eigener Pfad + eigene CSS-Klasse |

## Feedback von mir

- In den hirarchie wo die module eigene objeklte sind, wäre es super, wenn man auch in module reinzoomen könnte und ab einen gewissen zoom öffnetz sich das modul auf also die nächste ebene, mit rauszoomen kann man wieder eine ebene raus gehen, zoom mit mausrad meine ich

---

# Konzept: `:LibBrowse` — die Map im Editor (`ui.kit`)

> Status: **umgesetzt** (N-A bis N-D in einem Zug). Modul:
> `lua/lib/nvim/docmap/browse/` (`source.lua` = Datenherkunft, `view.lua` =
> pure State→Zeilen, `init.lua` = Layout/State/Keymaps). Command `:LibBrowse
> [live] [modul]` neben `:LibMap` registriert, Tests in
> `docs/TESTS/docmap_browse_spec.lua`, Doku in `browse/README.md` +
> `docs/EXAMPLES/docmap-browse.lua`.
>
> **Zwei Fehler, beide erst durchs Benutzen gefunden, nicht durchs Lesen:**
>
> 1. **Artefakt ≠ In-Memory-IR.** `to_json` schreibt `nodes` als **Array** in
>    Walk-Reihenfolge (genau das macht die Datei byte-deterministisch — die
>    Key-Reihenfolge eines JSON-Objekts wäre es nicht) und hat gar kein
>    `order`-Feld. Im Speicher ist `nodes` eine Map und `order` existiert.
>    Ohne Rehydrierung fand *jeder* Node-Lookup nichts, der Browser zeigte
>    „no such node" für alles. Dazu: `null` dekodiert per Default zu
>    `vim.NIL`, was **truthy** ist — `node.module or node.name` hätte
>    „userdata: 0x…" gerendert und `types_detail == nil` (das „LuaLS lief
>    nie"-Signal) wäre nie wahr geworden. Also `luanil` beim Dekodieren.
> 2. **Namespace-Auflösung, exakt derselbe Bug wie bei `:LibMap graph`
>    (Debug-Runde Punkt 4).** `:LibBrowse lib.nvim.fs` landete still auf der
>    Wurzel, weil `lua/lib/nvim/fs` keine `init.lua` hat und damit kein
>    `@module` deklariert. Jetzt über das schon dafür exportierte
>    `command.find_node` statt einer zweiten Kopie der Ableitung.
>
> Dazu ein echter Defekt in der eigenen Interaktion: `<CR>` wertete einen
> gecachten Cursor-Index aus, den nur ein `CursorMoved`-Autocmd pflegt — mit
> Cursor auf Zeile 3 stieg es in Zeile 1 ab. Aktionen lesen die
> Fensterposition jetzt direkt; der Cache dient nur noch dem Redraw.
>
> Baut auf `lib.nvim.ui.kit` (`layout.mount`, `surface`, `picker`) und dem
> vorhandenen IR auf — kein neuer Scanner.

## N0. Was das ausdrücklich *nicht* ist

**Nicht das HTML-Diagramm im Terminal.** Boxen mit Verbindungslinien brauchen
Pixel: freie Positionen, Kurven, stufenlosen Zoom. Ein Terminal gibt ein festes
Zellraster — was dabei herauskommt, ist eine schlechtere Version der Seite, die
es schon gibt, und niemand würde sie der Seite vorziehen.

Der Editor-View ist deshalb ein **Navigator über dieselben Kanten**, kein
Zeichner. Die Hierarchie darf ein ASCII-Baum sein (das kann Text gut); Deps und
Calls werden **Listen**, keine Graphen.

## N1. Warum es ihn trotzdem geben soll

Drei Dinge kann der Editor, die die generierte Seite prinzipiell nicht kann:

1. **Zum Quelltext springen.** `<CR>` auf eine Funktion öffnet die Datei an der
   Zeile. Die HTML-Seite kann bestenfalls auf GitHub verlinken.
2. **Quickfix füllen.** „Alle Aufrufer von `M.read` in die Quickfix-Liste" ist
   genau das, wofür ein Editor-UI gebaut ist — und der Punkt, an dem die
   Call-Kanten aufhören, hübsch zu sein, und anfangen, Arbeit zu sparen.
3. **Live sein.** Die Seite ist ein Artefakt und zeigt den Stand des letzten
   `:LibMap`. `docmap.install({ watch = true })` liefert eine IR, die sich beim
   Speichern selbst aktualisiert.

Wenn nur eins davon übrig bliebe, wäre es (2).

## N2. Datenquelle — gemessen, nicht geraten

| Weg | Kosten |
|---|---|
| `scan()` über lib.nvim | **0,65 s** (283 Nodes) |
| `check()` | 0,05 s |
| `module_map.json` einlesen + dekodieren | **0,01 s** (810 KB) |

Das entscheidet den Default: **erst das Artefakt lesen**, nicht scannen. 0,65 s
blockierendes nvim beim ersten Öffnen ist der Unterschied zwischen „geht auf"
und „hängt". Also:

- Default: `docs/map/module_map.json` laden (10 ms). Fehlt es oder ist es älter
  als die neueste Quelldatei → Hinweiszeile „Karte ist veraltet — `:LibMap`"
  statt stillschweigend falscher Daten.
- `:LibBrowse live` → `install({ watch = true })`, einmal 0,65 s zahlen, dafür
  aktualisiert sich der View beim Speichern über `on_change`.

Das Artefakt enthält seit dem Graph-Umbau alles Nötige: `edges` mit `kind`,
`requires`/`required_by`, `symbols`, `stats`. Nur `types_detail` fehlt ohne
`:LibMap full` — dann entfällt der Types-Modus, wie im Browser auch.

## N3. Layout

`ui.kit.layout.mount` gibt benannte Slots als `Surface`-Handles zurück
(`set_lines`, `set_title`, `focus`, `on_close`, plus `.bufnr`/`.winid` für
eigene Keymaps). Drei Slots:

```
┌─ list ───────────────┬─ detail ─────────────────┐
│ ▸ lib.nvim.fs        │ lib.nvim.fs.read         │
│   lib.nvim.git       │                          │
│ ▸ lib.nvim.store     │ Reads a file…            │
│   …                  │ @param path string       │
│                      │ 3 callers · 1 callee     │
├──────────────────────┴──────────────────────────┤
│ lib.nvim ▸ fs ▸ read     [calls ←]  q:close     │
└─────────────────────────────────────────────────┘
```

Keymaps setzt der Aufrufer auf `slots.list.bufnr` — `layout.mount` selbst hat
dafür keine Schnittstelle, was für diesen Fall reicht, aber erwähnenswert ist,
falls mehr Komponenten das brauchen.

## N4. Modi und Tasten

Vier Modi, dieselben wie im Browser, umgeschaltet mit einer Taste:

| Taste | Wirkung |
|---|---|
| `1`…`4` | Struktur / Deps / Calls / Types |
| `j` `k` | Auswahl bewegen (Detail folgt sofort) |
| `<CR>` | eine Ebene hinein (Struktur) bzw. der Kante folgen (Deps/Calls) |
| `-` / `<BS>` | eine Ebene heraus |
| `<C-o>` / `<C-i>` | zurück / vorwärts im Besuchsverlauf |
| `h` / `l` | Richtung: eingehend / ausgehend (Deps, Calls) |
| `+` / `_` | Tiefe ±1 |
| `gd` | Quelle an der Zeile öffnen (schließt den View) |
| `gq` | aktuelle Liste in die Quickfix-Liste |
| `/` | Fuzzy-Suche über alle Module und Funktionen (`ui.kit.picker`) |
| `q` `<Esc>` | schließen |

Der Verlaufsstapel ist die Entsprechung zur Browser-History. Er ist hier
*wichtiger* als dort: ohne Adresszeile gibt es kein „wo war ich".

## N5. Phasen

```
N-A  Struktur-Navigator: Layout, Liste, Detail, Baum, gd, q        ✅
N-B  Deps- und Calls-Modus + Richtung/Tiefe                        ✅
N-C  Quickfix (gq) + Fuzzy-Sprung (/)                              ✅
N-D  Live-Modus über install({watch=true}) + on_change             ✅
```

Alle vier in einem Zug umgesetzt statt gestaffelt: die Modus-Umschaltung ist
die tragende Achse des ganzen Views (`state.mode` steuert Liste, Detail *und*
Statuszeile), N-A allein hätte sie eingebaut und N-B hätte sie sofort wieder
angefasst.

**Abweichungen von der Konzeptskizze:**

- **`gd` auf einer Calls-Zeile springt zur *Deklaration*, nicht zur
  Call-Site.** Die `line` einer Call-Kante ist die Stelle, an der der Aufruf
  *steht* — also in der Datei, die man ohnehin gerade ansieht. Damit hätte
  jede Zeile der Liste zurück an den Ausgangspunkt geführt. Die Call-Site
  bleibt als `site_line`/`site_source` erhalten.
- **`gq` und `gd` schließen den View.** Die Floats liegen über dem ganzen
  Editor; „zu einer Datei springen", die man nicht sehen kann, ist kein
  Sprung.
- **Externe Requires stehen mit in der Deps-Liste** (als `○`, nicht
  navigierbar). Sie ganz wegzulassen lässt ein Modul weniger Abhängigkeiten
  haben, als es hat.

## N6. Risiken und offene Fragen

| Risiko | Umgang |
|---|---|
| Wird doch ein schlechter Graph-Zeichner | Listen statt Kanten; wer das Bild will, bekommt `:LibMap graph` |
| 0,65 s Blockade beim Öffnen | Artefakt-First (10 ms); Live-Scan nur auf Ansage |
| Veraltetes Artefakt zeigt Unsinn | Mtime-Vergleich gegen die Quellen, sichtbarer Hinweis |
| `layout.mount` hat keine Keymap-Schnittstelle | Keymaps über `slot.bufnr`; falls mehr Komponenten das brauchen, gehört es in `ui.kit` |
| Zwei UIs driften auseinander | Beide lesen dieselbe IR; alles Ableitbare bleibt abgeleitet, nichts wird doppelt gepflegt |
| Types-Modus ohne `--full` leer | Wie im Browser: erklärende Zeile statt leerer Liste |

---

# Feature-Ideen (nach Wert/Aufwand sortiert)

> Stand: **alle sieben umgesetzt** (F1/F2/F7 zusammen in Commit `5a3c520`, F3
> in `3b8f184`, F4 in `7cfe261`, F6 in `7b7d879`, F5 zuletzt in `c40d2ec` —
> alle in lib.nvim, gepusht auf `main`). Die vier Kanten-Arten (`require`,
> `call`, `type`, plus `requires_external`) waren das Kapital, aus dem fast
> alles davon fiel.

## F1. `:LibMap why <a> <b>` — der kürzeste Abhängigkeitspfad ✅ umgesetzt

> Aufwand: **~2 h**. Wert: hoch.

„Warum zieht `lib.nvim.ui.kit` am Ende `lib.nvim.fs` herein?" ist eine Frage,
die man beim Aufräumen ständig hat, und der Graph beantwortet sie exakt: BFS
über die `require`-Kanten, kürzester Pfad, ausgegeben als Kette.

```
:LibMap why lib.nvim.ui.kit lib.nvim.fs
  lib.nvim.ui.kit → lib.nvim.ui.kit.surface → lib.nvim.window → lib.nvim.fs
                                              (lazy)
```

Lohnt sich, weil es die Frage beantwortet, für die man sonst den Deps-View von
Hand abläuft. Load-time- und Lazy-Kanten sind schon unterschieden, der Pfad
kann also dazusagen, ob er beim Laden oder erst beim Aufruf entsteht — was den
Unterschied zwischen „muss weg" und „ist in Ordnung" ausmacht. Im Browser als
fünfter Modus, im Editor als eigener `:LibBrowse`-Modus.

## F2. Blast-Radius: was bricht, wenn ich das ändere ✅ umgesetzt

> Aufwand: **~2 h**. Wert: hoch.

Die transitive Hülle von `required_by` ist die Antwort auf „wie riskant ist
diese Änderung". Sie steht schon in den Kanten, ist aber nirgends sichtbar.

- Detail-Pane und Browse-Detail: eine Zeile `impact: 37 Module, 4 direkt`.
- `:LibBrowse` bekommt `gI` — die ganze Hülle in die Quickfix-Liste.
- Optional als Check: ein Modul mit sehr großem Radius *und* ohne README ist
  ein Kandidat für „dokumentieren, bevor es jemand anfasst".

Der Reiz ist, dass es dieselbe Zahl vor und nach einem Refactor gibt. Ein
Umbau, der den Radius halbiert, hat nachweislich etwas verbessert.

## F3. `:LibMap diff <ref>` — was hat dieser Branch an der Struktur geändert ✅ umgesetzt

> Aufwand: **~4 h**. Wert: hoch, besonders für Review.

Beide Seiten sind IRs, der Vergleich ist ein Mengen-Diff:

```
:LibMap diff HEAD~5
  + Modul   lib.nvim.system.job
  + 12 Funktionen, - 3
  + Abhängigkeit  lib.nvim.docmap.browse → lib.nvim.ui.kit
  ! Zyklus neu    lib.a ↔ lib.b
  ! Blast-Radius  lib.nvim.notify  29 → 34
```

Das ist der Punkt, an dem das committete Artefakt aufhört, nur ein Bild zu
sein, und anfängt, ein *Vergleichspunkt* zu sein — es liegt ja bereits in jedem
Commit. Als CI-Schritt auf einem PR wäre die Ausgabe eine Zusammenfassung, die
kein Mensch von Hand erstellt.

Aufwandstreiber: die alte Fassung besorgen (`git show <ref>:docs/map/module_map.json`)
und ältere Schema-Versionen tolerieren, statt an ihnen zu scheitern.

## F4. `@internal` — die öffentliche Fläche schärfen ✅ umgesetzt

> Aufwand: **~1 h**. Wert: mittel, aber Voraussetzung für F5.

Ein Tag im Doc-Block, der eine Funktion als nicht-öffentlich markiert. Wirkung:
`undocumented-param` überspringt sie, der Map-Baum kann sie ausblenden
(Schalter), und F5 kann sie überhaupt erst sinnvoll auswerten.

Billig, weil `functions.lua` die Tags schon parst — es ist ein `elseif`.

## F5. Tote Funktionen (opt-in, nur `info`) ✅ umgesetzt (2026-07-28, Commit `c40d2ec`)

> Aufwand: **~3 h** geschätzt, gebraucht: deutlich weniger — die Fallen-
> Analyse unten war schon vollständig, nur noch als `check_dead_functions` in
> `lua/lib/nvim/docmap/check.lua` umgesetzt. Wert: mittel.

Neuer Check `dead-function`, immer `info`-Severity: eine Funktion ohne
einen einzigen auflösbaren `kind="call"`-Aufrufer im Baum *ist* ein Kandidat.
Die Falle blieb genau die beschriebene — eine Bibliothek besteht aus
Funktionen, die absichtlich keinen internen Aufrufer haben — also greift der
Check nur dort, wo die Aussage trägt:
- `local function` auf Modulebene ohne Aufrufer (eindeutig tot — von außerhalb
  der eigenen Datei ohnehin unerreichbar);
- mit `@internal` markierte Funktionen ohne Aufrufer;
- alles andere (gewöhnliche exportierte, nicht-`@internal` Funktionen) nur,
  wenn `opts.dead_code = true` gesetzt ist — sonst würde der Check die halbe
  öffentliche API melden und wäre sofort wertlos.

Über lib.nvim selbst: 76 `dead-function`-Treffer im Default-Modus (0 Errors,
`--check` bleibt grün). Neue Tests in `docs/TESTS/docmap_spec.lua` (6 Fälle:
lokale Funktion mit/ohne Aufrufer, `@internal` mit/ohne Aufrufer, exportierte
Funktion mit/ohne Aufrufer unter `opts.dead_code`). README-Tabelle und
`ANNOTATIONS.md`s `@internal`-Referenzliste aktualisiert.

## F6. DOT-/Graphviz-Export ✅ umgesetzt

> Aufwand: **~1 h**. Wert: mittel.

`:LibMap graph deps --dot > deps.dot`. Graphviz kann Dinge, die weder das
Layer-BFS im Browser noch Mermaid können: echte Kantenführung, Ranking,
Cluster nach Namespace, und Ausgabe in Druckqualität. Der Renderer ist im
Kern dieselbe Kantenschleife wie `mermaid.render_deps`.

## F7. `gO` — von `:LibBrowse` in die HTML-Seite springen ✅ umgesetzt

> Aufwand: **~30 min**. Wert: klein, aber verbindet die zwei Hälften.

Der Editor-Navigator kennt Modus, Zentrum, Richtung, Tiefe und Funktion. Der
gesamte Zustand der HTML-Seite steckt in ihrem URL-Fragment. `gO` ist damit
buchstäblich ein `format()` plus `:LibMap open` — und beantwortet „das will ich
jetzt doch als Bild sehen", ohne die Stelle erneut zu suchen.

## Bewusst *nicht* auf der Liste

| Idee | Warum nicht |
|---|---|
| Artefakt beim Speichern automatisch neu schreiben | Erzeugt Diffs, die niemand beabsichtigt hat — dieselbe Begründung, mit der der Pre-Commit-Hook nicht regeneriert. Seit der CI-Job Staleness fängt, ist der Nutzen ohnehin weg. |
| Den Graphen im Terminal zeichnen | Bereits in `browse/README.md` ausargumentiert: ein Zellraster kann das nicht besser als die Seite, die es schon gibt. |
| Vollständiger Lua-Parser für einen perfekten Call-Graph | Die vier exakten Formen decken diesen Baum ab; der Rest ist dynamischer Dispatch, den auch ein Parser nicht sieht. Der Aufwand steht in keinem Verhältnis. |
| Metriken über die Zeit (Trend-Diagramme) | Bräuchte eine Historie, die niemand pflegt. F3 beantwortet dieselbe Frage punktuell und ohne Datenhaltung. |

## Reihenfolge, wenn es nach mir ginge — ✅ alle sieben umgesetzt, in genau dieser Reihenfolge

**F1 → F2 → F7** zuerst: zusammen etwa ein halber Tag, alle drei fallen direkt
aus vorhandenen Daten, und sie machen aus der Karte ein Werkzeug zum
*Entscheiden* statt nur zum Anschauen. **F3** danach, weil es den größten
Einzelnutzen hat, aber auch am meisten kostet. **F4/F5** zuletzt — tote
Funktionen waren ein tatsächliches Problem genug, um den Check zu bauen statt
ihn wegzuklicken.

Damit sind alle in diesem Dokument geplanten Bausteine (Phasen A–G, N-A–N-D,
Z-A–Z-D, F1–F7) umgesetzt. Offen bleibt nur der Backlog-Eintrag B1
(Laufzeit-Inspektion), der explizit *nicht* Teil von docmap ist, sondern ein
eigenes zukünftiges Werkzeug.

---

# Backlog

## B1. Laufzeit-Inspektion eines geladenen Moduls

**Nicht** von docmap zu erledigen — bewusst als eigenes Werkzeug vorgemerkt.

docmap liest Quelltext; nichts wird ausgeführt. Was es zeigen kann, ist die
*statische* Modulfläche: `local X = {}`, `M.defaults = {...}`, Konstanten,
Load-Time-Bindings. Was es prinzipiell **nicht** zeigen kann:

- echte Instanzen und ihr Zustand zur Laufzeit,
- worauf die Metatable-/Lazy-Strategien in `lib.nvim.require` tatsächlich
  auflösen (syntaktisch steht dort nichts),
- tatsächliche Feldwerte, `__index`-Ketten, was `setup()` in eine Config
  geschrieben hat.

Ein zweiter Modus könnte im laufenden nvim `require("mod")` aufrufen und die
zurückgegebene Tabelle begehen. Das ist ein **anderes Vertrauensmodell**: er
führt fremden Code aus, hat Nebenwirkungen, hängt vom Zeitpunkt ab und darf
deshalb niemals in `--check` oder in ein committetes Artefakt fließen. Eher ein
`:LibInspect <modul>` neben der Map als ein Teil von ihr.

Offene Fragen, bevor das lohnt: Zyklen und Tiefenbegrenzung beim Begehen,
Umgang mit `__index`-Funktionen (aufrufen? nur melden?), und ob das Ergebnis
überhaupt woanders hingehört als in ein `ui.kit`-Fenster.

---

# Konzept: Semantischer Zoom im Hierarchy-View

> Status: **umgesetzt** (`b6fae49`). Z-A bis Z-D in einem Zug, plus die
> Modul-Infos/Stats aus deinem zweiten Feedback (`aae7970`).
>
> Abweichung vom Konzept unten, gefunden beim Testen: die Schwelle darf nicht
> auf dem *Zustand* („`z >= 1.8`") feuern, sondern nur auf dem **Überschreiten**.
> Sonst kann der Zoom oberhalb der Schwelle liegenbleiben — und dann löst die
> nächste Rad-Bewegung in *beliebiger* Richtung einen Drill nach innen aus, auch
> ein Rausdrehen. Nebeneffekt der Korrektur: eine verweigerte Ebene (Blatt,
> Wurzel) darf den Zoom stehenlassen, ohne bei jedem weiteren Klick erneut zu
> feuern — genau das macht „auf ein Blatt weiter reinzoomen, um es zu lesen"
> möglich.
>
> Ebenfalls ergänzt: ein Drill auf die *bereits zentrierte* Box ist eine
> Verweigerung, keine Navigation — sonst setzt der Zoom grundlos zurück.
>
> **Modul-Infos** (zweites Feedback): `symbols.lua` liefert Tabellen,
> Konstanten und Load-Time-Bindings auf Modulebene; `node.stats` zählt Module,
> Namespaces, `.lua`/`.md`/sonstige Dateien, Lua-Zeilen, Funktionen, Symbole
> und Typen — aggregiert über den *ganzen Teilbaum*. Beides im Detail-Pane.
> Über lib.nvim: 129 Module, 375 Lua-Dateien, 62 Markdown, 33 662 Zeilen,
> 894 Funktionen, 600 Modul-Symbole.

## Z0. Zwei Zooms, die nicht dasselbe sind

Der Wunsch enthält zwei Mechanismen, die im Code getrennt bleiben müssen,
sonst wird beides halb:

| | Was passiert | Kostet |
|---|---|---|
| **Geometrischer Zoom** | Dasselbe Diagramm größer/kleiner. Nichts ändert sich am Inhalt. | Eine CSS-`transform: scale()`, GPU-billig, kein Relayout |
| **Semantischer Zoom** | Beim Überschreiten einer Schwelle wird *ein anderer Ausschnitt* gezeichnet — eine Ebene tiefer bzw. höher. | Ein `navigate({center})` — also exakt der Pfad, den Doppelklick heute schon geht |

Der geometrische Zoom ist das **Gefühl** zwischen zwei Ebenen, der semantische
ist der **Sprung**. Google Maps macht genau das: stufenlos skalieren, und an
bestimmten Zoomstufen kippt der Karteninhalt um.

**Wichtig:** „das Modul öffnet sich auf" hat zwei mögliche Lesarten, und die
Wahl entscheidet über den Aufwand:

- **(a) Re-Zentrieren** — das Modul unter dem Cursor wird zum neuen Zentrum,
  seine Kinder werden zur nächsten Layer. Nutzt `state.center` und das
  vorhandene Layout unverändert. **Empfohlen.**
- **(b) In-Place-Expansion** — die Kinder erscheinen *innerhalb* der Box, die
  Geschwister bleiben stehen. Das ist ein Containment-Layout (Treemap-artig),
  ein grundsätzlich anderes Verfahren als das aktuelle Layer-BFS, und es
  verträgt sich schlecht mit Deps/Calls, die keine Containment-Hierarchie sind.

Deine Formulierung („mit rauszoomen kann man wieder eine ebene raus gehen")
beschreibt (a): raus = zum Elternknoten. Das Konzept unten setzt (a).

## Z1. Interaktionsmodell

| Geste | Wirkung |
|---|---|
| Mausrad über dem Graphen | Stufenlos skalieren, Ankerpunkt ist der Cursor |
| Rad hoch über Schwelle | **Drill-down**: `center` = Modul unter dem Cursor |
| Rad runter unter Schwelle | **Drill-up**: `center` = Elternknoten (wie `▲ Up`) |
| `Shift` + Rad | Horizontal pannen, statt zoomen |
| Ziehen mit gedrückter Maustaste | Pannen (fehlt heute auch schon) |
| `+` / `-` / `0` | Zoom rein / raus / auf 100 % zurück |

**Offene Entscheidung — Rad ohne Modifier oder mit `Strg`?**
`#hgraph-wrap` ist heute ein scrollbarer Kasten *innerhalb* einer Seite; Rad
scrollt dort. Wenn Rad künftig zoomt, muss `preventDefault` her (und damit
`{ passive: false }`), und wer scrollen will, ist überrascht.
**Empfehlung: Rad = Zoom**, weil der Pane als Canvas gelesen wird und nicht als
Text, plus `Shift`+Rad zum Pannen und ein Hinweis in der Legende. Trackpad-Pinch
kommt ohnehin als `ctrl+wheel` an und wird gleich behandelt.
Wer das anders will: `ctrl+wheel`-only ist eine Einzeilen-Änderung an der
Bedingung — aber dann fühlt sich der Zoom nicht wie der gewünschte an.

## Z2. Schwellen und Hysterese

Naiv („bei `z ≥ 1.5` eine Ebene runter, danach `z = 1.0`") flackert: ein
minimales Zurückdrehen unterschreitet sofort die Gegen-Schwelle und springt
wieder hoch. Deshalb **asymmetrische Schwellen plus Cooldown**:

```
DRILL_IN     z >= 1.80   -> navigate({center: unterCursor});  z := 0.90
DRILL_OUT    z <= 0.55   -> navigate({center: parent});        z := 1.15
Z_MIN 0.35   Z_MAX 2.40  (harte Klammer, wenn kein Sprung möglich ist)
COOLDOWN_MS  260         (≈ ANIM_MS: eine Wischgeste darf nicht drei Ebenen fallen)
```

Nach einem Sprung liegt `z` bewusst *innerhalb* des Bandes, nicht auf der
Gegenschwelle — das ist die Hysterese.

**Kein Sprung möglich** (Blatt ohne Kinder beim Rein-, Wurzel beim
Rauszoomen): `z` an `Z_MAX`/`Z_MIN` klemmen und die betroffene Box kurz
pulsieren lassen (`.pulse` gibt es schon). Stillschweigend nichts tun liest
sich wie ein Bug.

## Z3. Ziel-Ermittlung

Das Modul unter dem Cursor, nicht das zentrierte:

1. `document.elementFromPoint(x, y)` → mit dem vorhandenen `boxOf()` zur Box.
2. Kein Treffer (Cursor im Leerraum) → die Box mit dem geringsten Abstand vom
   Cursor, aus `positions` gerechnet, **nicht** aus dem DOM gemessen.
3. Box ohne `_spec.recenter` (externe Requires!) → kein Ziel, klemmen.

Beim Drill-up ist das Ziel immer `byId[hcenter].parent` — unabhängig vom
Cursor, damit „raus" berechenbar bleibt.

## Z4. Umsetzung im Renderer

Der Punkt, an dem es sich mit dem bestehenden Code beißen könnte, und warum
nicht:

- **Layout bleibt analytisch.** Der Zoom ist eine `transform: scale(z)` auf
  einer *neuen* Zwischenebene `#hstage`, die Boxen und SVG umschließt.
  `positions` in px bleiben unangetastet — die README-Zusage „nie aus dem DOM
  gemessen" gilt weiter, und `reconcile()` muss nichts wissen.
- **Scrollfläche.** `transform` ändert die Layoutgröße nicht, sonst wächst der
  Scrollbereich beim Reinzoomen nicht mit. Also: `#hstage` bekommt die
  Transform, `#hgraph` bekommt `width/height = totalW*z / totalH*z`.
- **Ankerformel.** Damit der Punkt unter dem Cursor stehen bleibt:
  ```
  const r = wrap.getBoundingClientRect();
  const gx = (wrap.scrollLeft + ev.clientX - r.left) / z;   // Graph-Koordinate
  const gy = (wrap.scrollTop  + ev.clientY - r.top ) / z;
  z = clamp(z * Math.exp(-ev.deltaY * 0.0015), Z_MIN, Z_MAX);
  wrap.scrollLeft = gx * z - (ev.clientX - r.left);
  wrap.scrollTop  = gy * z - (ev.clientY - r.top);
  ```
- **Auto-Scroll unterdrücken.** `drawHierarchy()` scrollt heute das Zentrum in
  die Mitte. Nach einem Zoom-Sprung würde das gegen den Cursor-Anker
  arbeiten. Also ein Flag `suppressAutoScroll` für genau diesen Übergang —
  stattdessen die neue Zentrums-Box unter den Cursor legen, damit der Sprung
  räumlich zusammenhängt.
- **Zoom kommt NICHT in die History.** Gleiche Lektion wie beim Such-Preview
  (siehe README): nur der *Sprung* ruft `navigate()`, das Skalieren nie. Auch
  nicht in den Hash — Zoom ist Komfort, kein Zustand.
- **`ANIM_MS`-Transition** auf `#hstage` beim Sprung (nicht beim stufenlosen
  Rad, das muss 1:1 folgen), abgeschaltet unter `prefers-reduced-motion`.

## Z5. Level-of-Detail am Boxinhalt (Zugabe, billig)

Unter ~0.65 Skalierung ist die Summary-Zeile unlesbar und nur noch Grau.
Eine Klasse `#hstage.lod-min` blendet `.hsm`/`.hline` aus und lässt nur den
Namen stehen — reines CSS, kein Neuzeichnen. Über ~1.5 könnte umgekehrt eine
Zeile mehr erscheinen (Funktionszahl, Findings-Anzahl). Das ist der *zweite*
Sinn von „semantischem Zoom" und kostet fast nichts.

## Z6. Was in den anderen Views passiert

| View | Geometrischer Zoom | Drill |
|---|---|---|
| **Modules** | ja | ja — das ist der Anwendungsfall |
| **Types** | ja | Drill-down auf den besitzenden Node der Klasse; Drill-up = `▲ Up` |
| **Deps** | ja | **nein** — „eine Ebene tiefer" ist in einem Require-Graphen nicht definiert. Stattdessen bindet Rad+Schwelle dort auf `depth ±1`, was die inhaltlich passende Entsprechung ist |
| **Calls** | ja | wie Deps: Schwelle ändert `depth` |

Das ist bewusst *keine* Vereinheitlichung um jeden Preis: in Deps/Calls ist
die Tiefe die Achse, die „mehr/weniger zeigen" bedeutet, und sie existiert
schon als State und als Toolbar-Control.

## Z7. Phasen

```
Z-A  #hstage + geometrischer Zoom + Anker + Shift-Pan + Tastatur   (~½ Tag)
Z-B  Schwellen/Hysterese/Cooldown + Drill in Modules               (~½ Tag)
Z-C  LOD-Klassen am Boxinhalt                                      (~1 h)
Z-D  Types-Drill, Deps/Calls auf depth±1                           (~2 h)
```

Z-A ist für sich schon nützlich (der 90-Boxen-Modules-View ist heute ohne
Zoom mühsam) und lässt sich unabhängig bewerten, bevor Z-B die Magie draufsetzt.

## Z8. Risiken

| Risiko | Umgang |
|---|---|
| Rad-Hijacking überrascht | `Shift`+Rad pannt, Hinweis in der Legende, `ctrl+wheel` als Rückfalloption dokumentiert |
| Flackern an der Schwelle | Asymmetrische Schwellen + Cooldown, Reset *innerhalb* des Bandes |
| Eine Wischgeste fällt drei Ebenen | `COOLDOWN_MS` ≈ `ANIM_MS` |
| Anker kämpft gegen Auto-Scroll | `suppressAutoScroll` beim Zoom-Sprung, Zentrum unter den Cursor |
| History füllt sich mit Zoomstufen | Nur der Sprung ruft `navigate()`, Skalierung nie — dieselbe Regel wie beim Such-Preview |
| SVG-Export exportiert verzerrt | Export ignoriert `z` und schreibt das 1:1-Layout |
| Externe Boxen als Drill-Ziel | Haben kein `recenter` → werden als Ziel verworfen |

---

# Roadmap: Doxygen-Parität + Betrieb

> Status (Stand 2026-07-28): **D1–D3 umgesetzt**, D4 bewusst
> zurückgestellt. Vier Diagramm-/Feature-Lücken gegenüber Doxygen, gefunden
> durch einen gezielten Abgleich (Doxygen-Manual als Quelle, nicht nur aus dem
> Gedächtnis), plus zwei Betriebsfragen, die vor einer Umsetzung entschieden
> werden sollten statt nebenbei mitzuentscheiden.

## D1. Klassen-Hierarchie (Vererbung) ✅ umgesetzt (2026-07-28, Commit `a93fb1e`)

> Aufwand geschätzt ~1 Tag, tatsächlich deutlich weniger. Wert: hoch —
> Doxygens bekanntestes Diagramm hatte kein Äquivalent, obwohl die Rohdaten
> (`@class Foo : Bar`) längst überall im Baum stehen.

**Konzept-Korrektur, gefunden durch Nachmessen statt Annehmen:** die Parents
liegen auf **`defines[1].extends`**, nicht auf `entry.extends` wie unten
ursprünglich vermutet — und es ist ein **Array** (Mehrfachvererbung), je
Element `{ type = "doc.extends.name", view = "<Name>" }`. Gegen echte
`lua-language-server 3.18.2`-Ausgabe verifiziert, bevor eine Zeile Code
entstand. Ebenfalls geprüft: ein `@alias` trägt **nie** `extends`, auch wenn
er auf eine Klasse aliast — sonst hätte der Alias-Fall Vererbung erfunden,
die es nicht gibt.

Umgesetzt:
- Neuer Edge-Kind `"extends"` (`from_class`/`to_class`, kein `via` — nichts
  vermittelt die Beziehung). Eigener Sortier-/Append-Block, wie jeder
  Produzent.
- `luals.lua` löst die Parent-Liste auf; nicht auflösbare Parents bleiben auf
  `types_detail[].extends` lesbar, erzeugen aber keine Kante — dieselbe Regel,
  der `requires_external` für Requires außerhalb der Map folgt.
- Neue Hierarchy-View `"Inheritance"` (fünfter Button). Boxen zeigen die
  Parent-Liste (`: A, B`) bzw. `base` statt des nichtssagenden `class`.
  Kontextmenü-Eintrag, eigene Legende, eigene Kantenfarbe + Pfeilkopf
  (Pfeil zeigt auf die Basisklasse), SVG-Export eingeschlossen.

**Abweichung vom Konzept:** die View benutzt **nicht** das gemeinsame
`walk()`. `walk` legt jeden Seed auf Layer 0 — ein Modul deklariert aber
typischerweise Basisklasse *und* Subklassen zusammen, also sind alle Seeds und
die Hierarchie fiel auf eine einzige Zeile zusammen (im Browser gesehen:
`Lib.Cache.Opts` neben seinen eigenen `LoadOpts`/`SaveOpts`). Tiefe kommt
jetzt aus der Relation selbst: längster Pfad von einer parentlosen Klasse,
damit eine Klasse *immer* strikt unter **jedem** ihrer Parents landet, auch im
Diamant (an einem eigenen Fixture mit 3 Ebenen + Diamant verifiziert).

**Nebenbefund, mitgefixt:** *jeder* Empty-State im Hierarchy-Tab war
unsichtbar — die Meldung hing an `#hstage`, das seit dem Zoom-Umbau
`position:absolute` ist und damit keine Höhe an ein `#hgraph` liefert, dessen
explizite Höhe der Empty-Zweig gerade gelöscht hatte; `overflow` schnitt sie
weg. Jetzt an `#hgraph` — exakt das, was der Kommentar zwei Zeilen darunter
ohnehin schon behauptete. Bei Types/Deps/Calls selten, bei Inheritance der
Normalfall.

**Acceptance erfüllt:** `--full` über lib.nvim liefert 8 `extends`-Kanten;
`grep -rn '^---@class [^ ]* *:' lua/` findet 9 Deklarationen, davon ist
`Array<T>: { [integer]: T }` ein Tabellentyp statt eines benannten Parents und
erzeugt korrekt nichts. Null unaufgelöste Parents.

**Wichtig zu wissen:** das committete Artefakt unter `docs/map/` wird
**ohne** `--full` erzeugt (CI vergleicht es byte-genau und bräuchte sonst
`lua-language-server`). Types- *und* Inheritance-View sagen das beim Öffnen
explizit, statt leer zu bleiben. Erste Tests für `luals.merge` überhaupt —
die Funktion ist rein (IR + doc.json rein), braucht also kein LuaLS im Test.

## D2. Aggregierte Listen (Deprecated/Todo/Bug/Test) ✅ umgesetzt (2026-07-28, Commit `ef119bf`)

> Aufwand wie geschätzt (~3 h zusammen). Wert: mittel.

Neuer **Notes-Tab** (dritter Tab neben Tree/Hierarchy) mit vier Sektionen:
`@deprecated` (Daten existierten schon, nur nirgends gesammelt) plus die drei
neuen Tags `@todo`/`@bug`/`@test` in `parse_doc_block`.

**Abweichung vom Konzept:** die drei neuen Tags sind **Arrays**, nicht je ein
`string?` wie unten geplant. Doxygen sammelt einen Listeneintrag *pro
Vorkommen*, und eine Funktion mit zwei offenen Todos hat zwei Todos — ein
Skalar hätte den zweiten stillschweigend verschluckt. `@see`/`@overload`
etablieren dieselbe Form in derselben Datei bereits.

**Vorab geprüft, weil es über den Sinn des ganzen Features entscheidet:**
`lua-language-server` kennt diese Tags nicht, *diagnostiziert* unbekannte
Annotationen aber auch nicht — mit `--check --checklevel=Information` gegen
3.18.2 verifiziert, bevor die Tags eingeführt wurden. Ein Tag, das jedem eine
LSP-Warnung beschert, wäre keine Listenseite wert gewesen.

Ein Tab statt Doxygens vier Seiten: in einem gegebenen Baum sind drei dieser
Tags meist ungenutzt (in lib.nvim selbst aktuell **alle vier** — die Sektionen
zeigen 0), und vier meist leere Tabs wären vier Tabs Rauschen. Leere Sektionen
sagen das explizit, statt zu verschwinden — damit bleibt "hier ist nichts
deprecated" von "dieser Build hat es nicht gesammelt" unterscheidbar.

Wie geplant **nicht** als `check`-Finding: keine Drift, kein Fehler, und
Autoren-Todos haben im Exit-Code, an dem CI scheitert, nichts zu suchen.
Nebenbei: `serializeState` bekam einen eigenen Zweig für flache Tabs — sonst
hätte jeder geteilte Notes-Link ein sinnloses `view=modules` mitgeschleppt.

## D3. Alphabetischer Funktions-Index ✅ umgesetzt (2026-07-28, Commit `7d1cf24`)

> Aufwand wie geschätzt (~2 h). Wert: mittel.

Vierter Tab `"Index"`: alle **976** dokumentierten Funktionen von lib.nvim in
einem flachen Alphabet, mit Buchstaben-Sprungleiste; Klick öffnet das Modul im
Tree-Tab, `@internal`/`@deprecated` sind inline getaggt.

Sortiert nach **bare name**, `M.read` steht also unter **R**. Das `M.` ist die
lokale Tabellen-Konvention dieses Repos, nicht Teil des Funktionsnamens — 555
von 976 Einträgen unter einem einzigen "M" wären ein Index nur dem Namen nach.
`calls.lua` brauchte dieselbe Reduktion, sein `bare()` war die Vorlage. Namen
mit nicht-alphabetischem Anfang (`_evict`) sammeln sich unter `#`, statt
wegzufallen.

Im Editor bleibt es wie vermutet kosmetisch — der Fuzzy-Picker (`/`) deckt
dieselbe Frage ab, also kein `:LibBrowse`-Modus dafür.

**Verifikation ohne Browser:** die Browser-Vorschau nahm ab einem Punkt keine
neuen Dateien mehr an, also wurde das *ausgelieferte* `drawIndex()` unter Node
gegen die im generierten Artefakt eingebettete IR ausgeführt: 976 `<li>`, 27
Sektionen deren Zähler exakt 976 ergeben, `M.read` unter R, kein `M.*`
fehleinsortiert; beide Tag-Zweige an einem Fixture nachgewiesen.

## D4. Source-Browser — bewusst zurückgestellt, nicht verworfen

Doxygens `SOURCE_BROWSER=YES` rendert Quelltext syntax-highlighted inline,
mit anklickbaren Querverweisen. docmap verlinkt über `srcUrl()` nur nach
außen (GitHub-Blob oder `file://`). Grund, das NICHT nachzubauen: `:LibBrowse`s
`gd` springt bereits in den echten Editor an die echte Zeile — strikt besser
für tatsächliche Nutzung als eine statische HTML-Ansicht. Bleibt hier nur als
bewusste Nicht-Entscheidung dokumentiert, falls die Frage später nochmal
aufkommt (z.B. für jemanden ohne die Quelle lokal).

---

# Betriebsfragen (vor D1–D3 zu klären, nicht nebenbei)

## O1. `:LibMap` ganz ohne nvim starten — oder: nie mehr von Hand aktualisieren

Zwei verschiedene Wünsche, die sich leicht vermischen:

1. **Kein nvim-Prozess überhaupt** (echtes Standalone-CLI-Tool, kein
   `nvim --headless`). Nicht realistisch ohne kompletten Umbau:
   `scan.lua`/`functions.lua`/`calls.lua` hängen an `vim.treesitter`
   (Query-API, geparste Bäume), `luals.lua` an `vim.uv`/`vim.system`,
   `deps.lua`/`check.lua` an `vim.fn`/`vim.split` — im Kern die komplette
   Scan-Schicht. Alternativen wären ein eigenständiges `tree-sitter`-CLI-Binary
   mit eigener Query-Auswertung außerhalb von Lua, oder ein vollständiger
   Treesitter-Lua-Binding-Stack ohne Neovim (z.B. `ltreesitter`) — beides ein
   eigenes, mehrtägiges Projekt, keine Erweiterung von docmap mehr, sondern
   ein Parallel-Scanner, der mit der Zeit von der echten Implementierung
   abdriftet.
2. **Kein *interaktives* nvim** — das gibt es bereits:
   `nvim --headless -l scripts/gen_map.lua` startet keine UI und läuft in CI
   genau so (`ea365bf`). Falls das der eigentliche Wunsch war: **schon
   erledigt**, nur vielleicht nicht als solches erkannt.

**Empfehlung:** (1) nicht verfolgen — der Aufwand steht in keinem Verhältnis,
wenn (2) den eigentlichen Schmerzpunkt schon deckt (ein Terminal-/CI-Kommando
ohne geöffneten Editor). Stattdessen den *tatsächlichen* Punkt angehen —
"ich vergesse, `:LibMap` nach neuen Modulen laufen zu lassen":

- **Git pre-commit Hook**, nicht "bei jedem Speichern" (das wurde oben schon
  bewusst verworfen — "Bewusst *nicht* auf der Liste" — weil es Diffs
  erzeugt, die niemand beabsichtigt hat). Ein Hook, der **vor** dem Commit
  `gen_map.lua` laufen lässt und `docs/map/*` bei Drift automatisch neu
  schreibt und mit-staged, erzeugt dagegen **keinen** überraschenden Diff —
  er wird Teil desselben Commits, den man ohnehin gerade macht, nicht ein
  nachträglich entdeckter.
- CI (`--check`) bleibt das Sicherheitsnetz für den Fall, dass der Hook
  umgangen wird (`--no-verify`) — das ist bereits so eingerichtet.

**Offene Frage:** Hook nur lokal (`.git/hooks/pre-commit`, nicht versioniert,
einmal selbst installiert) oder über ein Tool wie `lefthook` versioniert und
für jeden Checkout automatisch aktiv? Für ein Ein-Personen-Repo spricht viel
für die einfache lokale Variante ohne zusätzliche Abhängigkeit.

## O2. Docmap in ein eigenes Plugin auslagern — mitdenken, nicht jetzt entscheiden

Nur als Überlegung festgehalten, keine Entscheidung. Stand heute: **22
Lua-Dateien, 8682 Zeilen** in `lua/lib/nvim/docmap/` allein, plus **1537
Zeilen** Tests (`docmap_spec.lua` + `docmap_browse_spec.lua`) — das ist groß
genug, um sich vom Rest von `lib.nvim` (kleine, fokussierte Utility-Module)
deutlich abzuheben. Eher eine eigenständige Anwendung *auf* `lib.nvim` als
ein Teil davon.

- **Dafür:** eigener Versions-/Release-Zyklus (docmap ändert sich schneller
  als der Rest von lib.nvim); wer `lib.nvim` nur wegen `ui.kit`/`fs`/etc.
  installiert, bekommt nicht ungefragt einen ganzen Doxygen-Klon mit;
  eigenes README/eigene Tests/eigene Issues statt alles unter einem Dach.
- **Dagegen:** docmap hängt an nichts anderem in `lib.nvim` außer
  `lib.nvim.ui.kit` (für `:LibBrowse`) — eine Auslagerung bräuchte entweder
  `lib.nvim` weiterhin als Abhängigkeit (dann ist wenig gewonnen) oder eine
  Entkopplung von `ui.kit` (Aufwand). Der Registrierungs-Mechanismus
  (`command.setup()`, `install()`) ist aber schon so gebaut, dass ein
  externes Plugin ihn 1:1 verwenden könnte, ohne dass docmap selbst sich
  ändern müsste — die Tür ist also bereits offen, falls die Entscheidung
  später fällt.

**Empfehlung:** jetzt nicht tun. D1–D4 zuerst fertig, dann anhand der
tatsächlichen Größe/Kopplung neu bewerten — eine Auslagerung rückgängig zu
machen ist teurer, als sie zu verschieben.

---

## O1 — Umsetzung (2026-07-28, `476d62e`)

Vollständiger Durchgang durch `docmap/`: A–G, N0–N6, F1–F7, Z0–Z8, D1–D3 alle
bereits ✅ (teils aus einer parallelen Session, beim Rebase integriert). D4
bleibt bewusst zurückgestellt (siehe oben). Einziger konkret offene Punkt war
O1.

Umgesetzt anders als hier ursprünglich skizziert, aus einem neuen
Anforderungs-Detail: der Hook soll sich **ohne Änderung an docmap selbst** in
jedem anderen Plugin einsetzen lassen, das docmap als Library verwendet — nicht
nur in diesem Repo. Das schob die Entscheidung von "lokal vs. lefthook" auf
eine andere Achse: `lefthook` würde jedem *Konsumenten* von `lib.nvim` eine
zusätzliche externe Abhängigkeit aufzwingen, nur weil `lib.nvim` selbst den
Hook so betreibt — das widerspricht dem Ziel direkt. Lokal (`core.hooksPath`)
gewinnt also nicht nur fürs Ein-Personen-Repo, sondern gerade *weil* es
portabel ist: ein Plugin kopiert eine Datei, keine neue Toolchain.

Was tatsächlich fehlte, war nicht Auto-Regenerierung+Staging (das hätte das
bestehende `README.md` explizit widersprochen — "a hook that regenerates and
stages output produces diffs the author never intended" — das war schon vor
diesem Task bewusst so entschieden, nicht Teil dieser Änderung), sondern dass
die CLI-Logik (`--check`/`--full`) fest in `scripts/gen_map.lua` verdrahtet
war und nicht wiederverwendbar.

Drei Änderungen in `lib.nvim`s `lua/lib/nvim/docmap/`:

- **`cli.lua`** (neu) — die komplette `--check`/`--full`-Logik aus
  `scripts/gen_map.lua` extrahiert, als `run(opts, argv) -> exit_code`. Kein
  `vim.cmd("cq …")` mehr darin — das bleibt Sache des Aufrufers, damit die
  Funktion selbst plain und testbar bleibt.
- **`scripts/gen_map.lua`** — auf 3 Zeilen Logik geschrumpft: cwd auflösen,
  `docmap.config` laden, `docmap.cli.run` aufrufen. Jedes andere Plugin kopiert
  diese Datei jetzt **wortwörtlich**.
- **`scripts/hooks/pre-commit`** — zum Template gemacht: drei Variablen oben
  (`SOURCE_DIR`, `OUT_DIR`, `GEN_SCRIPT`) sind der einzige projektspezifische
  Teil, der Rest ist generisches Shell. Kommentar im Skript verweist auf den
  neuen README-Abschnitt "Reusing docmap in another plugin".

`README.md` bekam den entsprechenden Abschnitt mit einem 3-Schritte-Rezept
(eigene `config.lua`, `gen_map.lua` kopieren, `pre-commit` kopieren + 3 Zeilen
anpassen) plus einem Minimalbeispiel für `Lib.Docmap.Opts`.

Verifiziert: `--check` grün vor/nach Regenerierung (deterministisch), stylua
sauber, luacheck sauber, volle Testsuite (`docs/TESTS/run.lua`) grün inkl.
`docmap_spec.lua`, Hook manuell gegen eine echte staged Datei ausgeführt (Exit
0). Gemergt `--ff-only` nach `main` (nach `rebase origin/main`, ein
Style-Fix-Commit war zwischenzeitlich dazugekommen), gepusht.

Damit ist O1 erledigt. Übrig laut diesem Dokument: **D4** (bewusste
Nicht-Entscheidung, kein Task), **O2** (bewusst "jetzt nicht"), **B1**
(explizit außerhalb docmap-Scope, eigenes künftiges Tool `:LibInspect`).

---



