# `lib.nvim` external-tool installer — analysis

> **Status: implemented.** All planned phases ship as `lib.nvim.deps`
> (`health`, `spec`, `pm`, `install`, `view`) plus the `:Lib deps
> show|install` routes. Two things changed during implementation and are
> corrected in place below: the command became `:Lib deps …` rather than a
> separate `:LibDeps` (§ "`:Lib deps`"), and `runtimepath` alone turned out
> to be insufficient for locating specs under lazy.nvim (§ "Runtime
> lookup") — open question 4 answered, negatively, with a fix.
> Originally written in response to: "Installer
> Modul, dass bei der Installation der Tools für das Plugin unterstützt.
> Beispiel: pdfport.nvim braucht für die Funktion 'API' Markdown/Images →
> PDF externe Tools (pandoc, img2pdf, tectonic, …). Man kann pdfport.nvim
> zwar ohne die verwenden, aber dann sind die Features nicht vollständig.
> Cool wäre ein Modul, das der User ausführen kann und das die für sein OS
> korrekten Tools installiert, ähnlich wie Mason oder LazyVim das machen.
> Wenn sich das so abstrahieren ließe, dass mehrere Plugins es nutzen
> können — perfekt. Wenn es zu speziell ist, dann nicht."
>
> **Short answer: the *detection* half is already generalized and should be
> consolidated further; the *installation* half is a real gap nothing in
> the ecosystem fills today, generalizes cleanly across ~10 plugins, and is
> worth building — but only as an explicit, confirmation-gated action, never
> as silent auto-install.** The split matters more than it first looks: one
> half is safe to ship broadly, the other touches the user's OS package
> manager and needs a narrower, more careful design.

## What already exists (verified, not assumed)

`lib.nvim` already ships the detection primitives every plugin needs:

- `lib.nvim.core.has_exec(bin)` / `first_available(candidates)` — memoized
  `vim.fn.executable` lookup.
- `lib.nvim.cross.platform.is_windows/is_macos/is_linux/is_wsl` — OS
  detection via uname + env-var + `/proc` fallback chain.
- `lib.nvim.cross.executable` — adds `exists`/`path`/`find` plus
  `mason_bin(name)`, which resolves Mason-managed binaries under
  `stdpath("data")/mason/bin`.

`pdfport.nvim` is the most fully-built consumer: its
`platform/init.lua` delegates every OS/executable check to the above, and
its `health.lua` wraps that in a local `check_exe(name, required)` helper
that reports found/missing via `:checkhealth` with a human install hint
("`pip install pdfplumber`", "install poppler-utils") — and stops there. It
never runs anything.

That same `check_exe`-shaped pattern is independently re-implemented,
grep-confirmed, in at least: `images.nvim` (`magick`, `chafa`,
`ueberzugpp`), `language.nvim` (`trans` for the shell translate provider),
`mdview.nvim` (`curl`, `tar`), `migrate.nvim` (`rg`), `open.nvim`,
`replacer.nvim`, `pickers.nvim`, `insights.nvim`, `gopath.nvim`,
`diff.nvim`, `runtime-analysis.nvim`, `github_stats.nvim`,
`filetree.nvim`. That is exactly the kind of duplication `lib.nvim` exists
to absorb — same argument that justified `lib.nvim.buffer.context` and the
`autocmd.dispatcher` concept.

**None of these plugins, and no part of `lib.nvim` itself, ever executes an
install command.** Every one of them only tells the user what to type.

## Is this Mason's job already?

Partly, and it's important to be precise about where the line is. Mason
already solves "install a dev tool for me" for LSP servers, DAP adapters,
linters and formatters — anything installable via `npm`/`pip`/`go`/`cargo`/
`gem`/`composer`, or as a prebuilt binary from a GitHub release, sandboxed
under `stdpath("data")/mason`. `lib.nvim.cross.executable.mason_bin`
already plugs into that.

But the tools named in the request — **pandoc, ImageMagick, tesseract-ocr,
poppler-utils (`pdftotext`/`pdftoppm`), tectonic, img2pdf, ffmpeg, chafa,
ueberzugpp** — are system packages with C-library and font dependencies.
They are not in Mason's registry model and are not going to be: Mason's
sandbox model (a private prefix per tool, no root, no system linking)
doesn't fit software that itself depends on system shared libraries.
`pdfport.nvim`'s own health output already reflects this split — Python
packages get a `pip install` hint, everything else gets a raw system
package name (`poppler-utils`, `tesseract-ocr`).

**The real gap is one layer further down: nothing wraps the actual OS
package managers** (`apt`/`dnf`/`pacman`/`zypper`/`apk`/`brew`/`scoop`/
`winget`/`choco`). That's the part of "like Mason" that doesn't exist yet.

## Does it generalize? Yes — concrete list, not hypothetical

| Plugin | External tools it degrades gracefully without |
|---|---|
| `pdfport.nvim` | `pdftotext`/`pdftoppm` (poppler), `tesseract`, `marker_single`/`pdfplumber`/`docling` (pip), `ollama`, `chafa`/`ueberzugpp`/`imgcat` |
| `images.nvim` | `magick` (ImageMagick), `chafa`, `ueberzugpp` |
| `language.nvim` | `trans` (translate-shell) |
| `mdview.nvim` | `curl`, `tar` |
| `migrate.nvim`, `replacer.nvim`, `insights.nvim` | `rg` |
| `pickers.nvim` | `fzf` |

Six plugins, at least 15 distinct binaries, every one detected today with a
hand-rolled variant of the same eight lines. That's a strong case for
sharing the *detection + health-report* half broadly. Whether **installing**
generalizes too is a separate question, answered below.

## Proposed shape: two layers, two risk levels

### Layer 1 — `lib.nvim.deps.health` (low risk, ship first)

A thin helper that replaces the repeated `check_exe`/`probe` pattern in
every plugin's `health.lua`, built directly on `lib.nvim.core.has_exec` and
`lib.nvim.cross.executable`:

```lua
local deps = require("lib.nvim.deps.health")

deps.report({
  { bin = "pdftotext", required = false, hint = "install poppler-utils", label = "pdftotext backend" },
  { bin = "tesseract",  required = false, hint = "install tesseract-ocr" },
  { python_module = "pdfplumber", hint = "pip install pdfplumber" },
})
```

This is pure refactor of code that already exists five times over, with no
new capability and no new risk — it doesn't run anything, same as today.
Good candidate to ship on its own regardless of what happens with layer 2.

### Layer 2 — `lib.nvim.deps.install` (the actual "Mason-like" part)

Two sub-concerns, kept separate because their maintenance burden differs:

**a) Package-manager detection (behavior, lives in `lib.nvim`).** One
function that answers "which package manager is available on this host":
checks `apt`/`dnf`/`pacman`/`zypper`/`apk` on Linux (plus WSL, which
`lib.nvim.cross.platform.is_wsl` already flags), `brew` on macOS,
`winget`/`scoop`/`choco` on Windows, in a fixed preference order, memoized
like `has_exec`.

**b) Per-tool package names and rationale (data, stays in each plugin —
but authored as Markdown, not Lua).** The package name for the same tool
differs per manager — `poppler-utils` (apt/deb) vs. `poppler`
(brew/pacman/dnf), `imagemagick` (apt/brew) vs. `magick` isn't even the
package name anywhere. This mapping is inherently plugin/tool knowledge,
not something `lib.nvim` can own — it has no way to know `pdfport.nvim`
wants `poppler-utils` specifically, or *why* it wants it. See the next
section for the authoring format — the follow-up request that prompted it
was specifically that a missing tool should be explainable, not just
listed: "tool xy installieren in diesem Plugin damit ... funktioniert",
not just "tool xy fehlt".

`lib.nvim.deps.install` consumes the parsed spec (see below): resolves the
current package manager, builds the install command (`sudo apt install
poppler-utils`, `brew install poppler`, `scoop install poppler`, …), and —
this is the part that must not be silent — **opens a terminal buffer
showing the exact command and lets the user confirm/run it**, the same way
`lib.nvim.window` already opens named scratch buffers. No `vim.fn.jobstart`
firing a `sudo` command in the background, no elevation prompt triggered
from inside Neovim.

```lua
require("lib.nvim.deps.install").run(missing_deps, {
  on_done = function(results) ... end,
})
-- opens a terminal split with the composed command(s) pre-filled,
-- run by the user, output visible live, exit code reported back
```

## Describing tools: `docs/INSTALL.md`

Follow-up question that shaped this section: *how do we make sure the
module can say "install tool xy in this plugin because it enables …"
rather than just "tool xy is missing"?* Two options were considered.

**Rejected: a Lua manifest** (the `pdfport/deps.lua` shape from an earlier
draft of this doc). Correct data, wrong authoring surface — it's invisible
on GitHub, requires reading source to know what a plugin depends on, and
duplicates what a README already half-states in prose.

**Chosen: a Markdown file, `docs/INSTALL.md`, that a plugin author
provides if they want the install module to know about their tools.**
Plain prose renders normally on GitHub; the parseable part is one small
fenced block per tool. This mirrors how `documentation.nvim`'s own IR
works — Markdown/comments as the human-facing source of truth, with a
narrow machine-readable subset lifted out of it — and it can reuse
`lib.lua.yaml.simple_parse`, which already exists in `lib.nvim` for
exactly this "small, structured, hand-written" case (no anchors, no flow
style, no block scalars — matches a short per-tool record fine, see that
module's README for the exact supported subset).

Template (`lib.nvim` ships this as a copyable starting point, e.g. under
`templates/`, next to the existing plugin-scaffold templates):

````markdown
# Optional external tools

`pdfport.nvim` works without any of these — each one only unlocks a
specific backend or renderer. Run `:LibDeps show pdfport.nvim` to see
what's missing on this machine, or `:LibDeps install pdfport.nvim` to
install what's missing.

```install-tool
bin: pdftotext
required: false
why: "Enables the fast plain-text extraction backend, no Python env needed."
pkg:
  apt: poppler-utils
  dnf: poppler-utils
  pacman: poppler
  zypper: poppler-tools
  apk: poppler-utils
  brew: poppler
  scoop: poppler
  choco: poppler
```

```install-tool
bin: tesseract
required: false
why: "Enables OCR extraction for scanned/image-only PDFs."
pkg:
  apt: tesseract-ocr
  brew: tesseract
  pacman: tesseract
  winget: UB-Mannheim.TesseractOCR
```
````

Parsing is two steps, both already covered by existing `lib.nvim` pieces:
extract every fenced block tagged ` ```install-tool ` from the file (a
~15-line line-scanner, no CommonMark parser needed — a fence delimiter is
just a line matching `` ```install-tool `` up to the next `` ``` ``), then
feed each block's body to `lib.lua.yaml.simple_parse`.

**`why` is a required field, not a convention.** The parser rejects — or
`:checkhealth`-warns on — any `install-tool` block missing it. This is the
actual answer to "how do we make sure the description gets written": not
by asking authors nicely, but by making a manifest entry without a reason
fail validation the same way a malformed `pkg` map would. `bin` and at
least one `pkg` entry are required for the same reason; `required`
defaults to `false` if omitted.

Plain-text single-line values only (the YAML subset has no `|`/`>` block
scalars) — `why` is meant to be one sentence anyway; anything longer
belongs in the surrounding Markdown prose, which a rendered "why" can link
to once (3) below exists (`see: "#ocr-backend"`).

## Runtime lookup: locating a plugin's spec

The install module needs to find *some other plugin's* spec file by name,
without caring which plugin manager installed it — `lib.nvim.deps`
shouldn't gain a dependency on lazy.nvim's internals just to answer "where
is `pdfport.nvim` on disk". `vim.api.nvim_get_runtime_file("**/docs/install.json", true)`
answers this manager-agnostically: any plugin on `runtimepath` is findable
this way, filtered down by the plugin-name path segment the caller asked
for (as a whole segment, so `pdfport.nvim` doesn't match a directory named
`my-pdfport.nvim-fork`).

**This turned out not to be enough, and the gap is large.** Open question 4
below asked whether the API resolves cleanly against real plugin-manager
layouts. Measured against an actual config rather than reasoned about:

```
120 plugins configured · 44 loaded at startup · 76 pending
```

lazy.nvim puts a plugin on `runtimepath` only when it *loads*. All 76
pending plugins were resolvable through lazy's own `dir` field while being
entirely absent from `runtimepath` — so a runtimepath-only lookup would
have silently failed for 63% of this user's plugins. "Silently" is what
makes it serious: an unfindable spec is indistinguishable from a plugin
that ships none.

The fix keeps the layering intact rather than adopting lazy.nvim as a
dependency: `runtimepath` stays the primary, manager-agnostic path (it
already covers packer, vim-plug, mini.deps, dev checkouts, and loaded lazy
plugins), and lazy.nvim's registry is consulted through a `pcall` **only
after** that misses. Other managers put plugins on `runtimepath` eagerly,
so this is specifically a lazy.nvim-shaped hole and lazy.nvim's registry is
the only thing that can fill it.

## `:Lib deps` — routes on the existing verb, not a new command

The command lives in `lib.nvim` itself rather than per-plugin — a user
reaching for "what does `replacer.nvim` need" shouldn't have to know
whether that plugin exposed its own verb for it.

The original sketch here was a standalone `:LibDeps`. That was wrong on
this repo's own terms: `lib.nvim` already owns a `:Lib` verb, and a second
top-level name for a subordinate feature is exactly the
`:VerbFeatureA`/`:VerbFeatureB` shape `lib.nvim.usercmd.composer` exists to
replace — its README opens by naming that anti-pattern. So the routes hang
off `:Lib`:

```vim
:Lib deps show replacer.nvim      " tools + why + present/missing, in a scratch split
:Lib deps install replacer.nvim   " compose + confirm + hand off to a terminal
:Lib deps show                    " which plugins ship a spec at all
```

`lib.nvim.deps.routes()` returns the route table and `lib.nvim_usrcmds`
merges it into the verb it already builds, so exactly one place owns `:Lib`.
Plugin-name arguments complete via a `DEPS_PLUGIN` composer type registered
lazily by `routes()` — registering a type is a side effect, and requiring
`lib.nvim.deps` must have none. A plugin can still add its own thin alias
(`:PdfPort deps` forwarding in) if it wants one, but nothing requires it:
shipping the spec file alone is enough to be covered.

## `documentation.nvim` integration: an optional `Deps` tab

`documentation.nvim`'s module map already has a precedent for exactly this
shape of addition: the **Notes tab** is Doxygen-style
Deprecated/Todo/Bug/Test lists, lifted from `---@deprecated`/`---@todo`/…
annotations found while walking the tree, rendered as a dedicated tab
alongside Tree/Hierarchy/Index/History/Analysis. A **Deps tab** — one
`install-tool` block's worth of rows (`bin`, `required`, `why`,
found/missing on the machine that generated the map) per plugin repo —
is the same move: a narrow, structured extra reading of the same kind of
source-adjacent file the Notes tab already reads, not a new subsystem.

This stays additive and optional, matching how `pdfport.nvim` treats
`lib.nvim.ui.kit` today: `documentation.nvim` gaining a `Deps` tab is a
`documentation.nvim`-side change (reads `docs/INSTALL.md` if present while
building its IR, renders nothing if absent), not something `lib.nvim.deps`
needs to know about or depend on. The coupling only runs one direction —
`documentation.nvim` already builds on `lib.nvim` (`fs`, `ui.kit`,
`usercmd`) per its own README, so it can `pcall(require, "lib.lua.yaml")`
the same block-parsing logic `:LibDeps` uses, rather than re-implementing
it. Worth raising in `documentation.nvim`'s own roadmap once `docs/INSTALL.md`'s
schema is stable — premature to design the render side before the format
it reads has shipped anywhere.

## Why not go further (no silent auto-install, no cross-distro guessing)

- **Elevation is not `lib.nvim`'s to grant.** `apt`/`dnf`/`pacman` need
  `sudo`; Windows package managers sometimes need an elevated shell. The
  module's job stops at *composing the correct command* and *showing it
  running in a buffer the user controls* — never at obtaining privileges
  itself.
- **Package names aren't 1:1 across managers**, sometimes not even across
  versions of the same distro. A generic "install poppler" resolver that
  guesses wrong is worse than today's `h_warn` + manual hint, because a
  wrong guess fails loudly mid-install instead of just not offering to
  help. This is why layer 2b (the name mapping) has to stay
  plugin-owned data, hand-verified per tool, not inferred.
- **Not auto-run on startup or on `require`.** Same rule already applied to
  `docmap.command.setup()` and the `autocmd.dispatcher` concept: requiring
  a lib module, or even calling `setup()`, must never touch the user's
  system. Installation is only ever a result of an explicit `:XDeps
  install` invocation.

## Recommendation

**Ship layer 1 now** (`lib.nvim.deps.health`) — it's a pure extraction of
code duplicated six times over today, zero new risk, immediate value via a
smaller `health.lua` in every consuming plugin.

**Design layer 2 as opt-in, per-plugin data + shared runner** — worth
building once two or three plugins actually want it (`pdfport.nvim` first,
it has the most backends and the most already-written manual hints to
replace), not as a big-bang cross-ecosystem rollout. The detection engine
and the terminal-buffer runner belong in `lib.nvim`; the tool→package-name
manifest belongs in each plugin, reviewed the same way any other hint
string is.

Phasing (all shipped):

1. ~~`lib.nvim.deps.health`~~ — the shared `check_exe`/`probe` replacement
   (`report`, plus `from_tools` bridging a parsed spec straight into
   `:checkhealth`). Migrating `pdfport.nvim`/`images.nvim`/`language.nvim`
   onto it is ordinary follow-up work in those repos, not a lib.nvim gap.
2. ~~`lib.nvim.deps.spec`~~ — fence-extractor + `lib.lua.yaml` bridge for
   `docs/INSTALL.md`, `vim.json.decode` for `docs/install.json`,
   `why`/`bin`/`pkg` validation, `find`/`plugins` lookup, and both
   templates under `templates/deps/`.
3. ~~`lib.nvim.deps.pm`~~ — manager definitions, per-OS preference order,
   detection, and command composition (`commands`/`render`).
4. ~~`lib.nvim.deps.install` + `lib.nvim.deps.view` + `:Lib deps
   show|install`~~ — plan computation, the report renderer, and the
   confirmed terminal handoff.
5. Still open, and deliberately so: **no plugin ships a spec yet.**
   `pdfport.nvim` is the natural first author (most backends, most
   already-written manual hints to replace); `images.nvim` second. Until
   one does, this is infrastructure with no production consumer, and the
   format's real ergonomics are untested by anyone but its own spec suite.
6. Still open: the `documentation.nvim` `Deps` tab, to be raised in that
   plugin's own roadmap once (5) has produced at least one real spec file.

## Open questions

1. ~~**WSL package manager.**~~ Resolved as leaned: `deps.pm` treats WSL as
   plain Linux. Inside WSL the distro's own manager *is* the right answer;
   the package-manager question is orthogonal to the render-target question
   other WSL branches solve.
2. ~~**Where does the schema's type live?**~~ In the module's own
   `@types/init.lua` (`lua/lib/nvim/deps/@types/`), matching this repo's
   convention that type definitions sit beside their module rather than in
   a shared `@types` bucket — `lib.nvim.cache` does the same.
3. ~~**Multiple missing deps in one run.**~~ Combined, as leaned, but the
   reason turned out to be sharper than "fewer sudo prompts": `winget`
   cannot take several packages per invocation at all (extra tokens become
   query terms), so `pm.commands` returns a *list* of argv lists — one
   combined command for managers that support it, one per package for those
   that don't. Callers must not assume there is exactly one.
4. ~~**Does `nvim_get_runtime_file` resolve cleanly against real
   plugin-manager layouts?**~~ **No** — measured, not assumed: 120 plugins
   configured, 44 loaded, 76 pending, and lazy.nvim only puts a plugin on
   `runtimepath` once it loads. See § "Runtime lookup" for the measurement
   and the two-step fix. This is the one question whose answer changed the
   design.
5. ~~**`why` length and tone enforcement.**~~ Implemented as leaned, a soft
   nudge: validation requires `why` to exist and be non-empty; `deps.view`
   additionally flags anything under 20 characters with a visible "say what
   the tool actually unlocks" line. Content quality isn't something a
   parser can decide, so it's surfaced where the author will see it instead
   of pretended to be validation.

## Still worth doing

- **`deps.health` migrations** in the plugins still hand-rolling `check_exe`
  — mechanical, but each is a change in another repo.
- **Windows elevation** is untested in practice. `choco` wants an elevated
  shell and `winget` raises its own UAC prompt; the current design punts
  both to the terminal the user submits the command in, which is the right
  boundary but has only been reasoned about, not tried on a machine that
  actually needs elevation.

## Follow-up: first-run popup + a `:checkhealth` hook

Second UX request, after the popup/inline-install one below: the normal
flow for installing one of these plugins is "see it on GitHub, copy the
lazy.nvim spec, paste it into `plugins/`, restart" — nowhere in that flow
does anyone read a README section about optional tools unless something
breaks later and they go looking. The ask: the *first* time a plugin
initializes after being installed, show the tools popup automatically, so
the information arrives without the user having to know to ask for it.
Ongoing, `:Lib deps show <plugin>` stays the way to check again.

**Where this could have gone wrong**, and why it doesn't: an automatic
popup is a real UI side effect, which sits right up against this module's
core rule ("requiring a module here never touches the user's editor by
itself"). The rule survives intact because the trigger is `deps.first_run
.show_once`, called from the *consuming plugin's own* `setup()` — an
explicit action the user already took (installing and configuring the
plugin), not something `lib.nvim.deps` decided to do on `require`. Nothing
under `lib.nvim.deps` calls `show_once` on anyone's behalf.

**Shipped:**

- `lib.nvim.deps.first_run` — `show_once(plugin_name, opts)`, persisted via
  `lib.nvim.cache.disk` (so "already shown" survives a restart, which is
  the whole point). No-op after the first call, including when there was
  nothing to show — a plugin with no spec, an empty spec, or nothing
  currently missing all still get marked seen, because this is a one-time
  welcome, not a watcher that might pop up later once something *becomes*
  missing.
- `deps.show_once` — a two-line re-export at the top level, since
  "`require("lib.nvim.deps").show_once(...)`" is the form a consuming
  plugin's `setup()` actually calls.
- `:Lib deps reset-first-run [plugin]` — clears the "seen" state, mainly
  for testing the flow without reinstalling.
- `deps.health.report_for(plugin_name)` — the `:checkhealth` half of the
  same idea (the user's own follow-up question): one line a plugin's
  `health.lua` adds, which locates and reports the plugin's own spec (same
  as `from_tools`, but without the plugin having to load its own spec by
  hand first) and points at `:Lib deps show` for the fuller report.

**Integration is three independent opt-ins** (ship a spec / add the
`health.lua` line / add the `setup()` line) — a plugin can take any subset.
None of the three make a spec mandatory, and skipping all three leaves a
plugin behaving exactly as it did before `lib.nvim.deps` existed. Full
reference: `:help lib.nvim-deps-integrating`.

## Follow-up: popup + inline install (`i`/`<CR>`/`I`)

`pdfport.nvim` shipping the first real spec surfaced a UX request the
original design didn't cover: a horizontal split for `:Lib deps show` reads
fine but isn't "install from here" — the request was specifically for
something closer to Mason's or LazyVim's install UI (press a key on an
item, its install runs, output streams into the same panel, collapsible).

**Shipped**, in `deps.view`:

- `show()` now opens a `lib.nvim.ui.kit` `viewer` popup (soft dependency,
  same as `pdfport.nvim`'s own mode picker) instead of a plain split, with
  `show_split` kept as the explicit fallback for when `kit` isn't
  installed.
- `i` installs the tool under the cursor. This could not be a blanket
  "run it in the background" the way Mason does, because Mason's installs
  are sandboxed and need no privilege — several of `deps.pm`'s managers do
  (`apt`, `dnf`, `pacman`, `zypper`, `apk`, and `choco`'s elevated shell).
  `pm.needs_terminal(manager)` decides per-manager: no elevation needed →
  install inline via `lib.nvim.cross.uv.spawn_stream`, output streamed live
  into the popup; elevation needed → the existing confirm-then-terminal
  handoff from `deps.install.run`, unchanged, just reachable from `i` too.
  This is the same safety boundary as before, not a relaxation of it — the
  inline path only exists where a plain backgrounded job was already safe.
- `<CR>` expands/collapses a tool's streamed output; `I` runs the bulk
  install unchanged.
- A tool's line flips `[missing]` → `[ok]` live once its inline install
  exits 0.

**Two real bugs found while building this**, both worth recording because
neither would show up in a casual read of the code:

1. **`t[#t + 1] = nil` is a Lua no-op.** `render()`'s original line-to-tool
   map built itself by appending to `line_tools` in lockstep with the
   rendered `lines` array — but assigning `nil` never grows a table's
   length, so every non-tool line (the header, blank lines, `##` section
   titles) silently failed to reserve its slot, and every tool line after
   it shifted one index earlier. The practical effect: `i`/`<CR>` on the
   popup would have resolved to the *wrong tool* the moment any non-tool
   line preceded a tool line — which is every real render, starting with
   line 1. Fixed with an explicit line counter instead of `#line_tools + 1`
   (`lua/lib/nvim/deps/view.lua`). Caught by a new test asserting
   `line_tools[header_line].bin` actually matches, not just that the
   header line exists.
2. **`core.has_exec` memoizes "not found" forever**, which is correct for
   its original callers (nothing they check installs mid-session) but wrong
   for an inline install that just changed the answer. Without a fix, a
   tool installed via `i` would report success but keep showing
   `[missing]` until Neovim restarted. Added `lib.nvim.core.forget_exec(bin)`
   — a narrow, single-purpose cache-buster — called once on a successful
   inline install, right before the re-render that reads the header status.
   Verified end-to-end (not just "doesn't error"): a test drops a real
   executable onto `$PATH` mid-run and confirms the cached miss survives
   until `forget_exec` clears it.
