# `lib.nvim.deps`

External-tool detection, declared-dependency spec parsing, and a
confirmation-gated install handoff, for plugins that degrade gracefully
without optional CLI tools (pandoc, ImageMagick, tesseract, poppler-utils,
…). Full design and rationale:
[`docs/ROADMAP/dependency-installer.md`](../../../../docs/ROADMAP/dependency-installer.md).

**Nothing here executes an install command.** `:Lib deps install` composes
the correct command for the host's package manager, asks first, then opens
a terminal with the command *typed but not submitted* — the user presses
Enter. That way a `sudo` password prompt is answered at a real terminal the
user opened, rather than by a backgrounded job with its prompt swallowed.
Requiring this module registers nothing and touches nothing.

| Submodule | What |
|---|---|
| `deps.health` | `:checkhealth` reporting for executables / Python modules — replaces the hand-rolled `check_exe` loop |
| `deps.spec` | Parse + validate `docs/INSTALL.md` / `docs/install.json`; locate them for any plugin |
| `deps.pm` | Package-manager detection + install-command composition |
| `deps.install` | Install-plan computation (pure) and the confirmed terminal handoff |
| `deps.view` | Render a plugin's tool report into lines / a popup with install keymaps |
| `deps.first_run` | Show a plugin's tool report once, ever — for a consuming plugin's own `setup()` |

## `:Lib deps` — the user-facing surface

Registered by `require("lib.nvim_usrcmds").setup()` (opt-in via its `deps`
option, default `true`), as routes on the existing `:Lib` verb rather than a
second top-level command:

```vim
:Lib deps show <plugin>      " tools + why + present/missing + install commands
:Lib deps show               " which plugins ship a spec at all
:Lib deps install <plugin>   " compose, confirm, hand off to a terminal
```

`<Tab>` completes plugin names that actually ship a spec.

## `lib.nvim.deps.health` — replace a hand-rolled `check_exe` loop

```lua
local health = require("lib.nvim.deps.health")

health.report({
  { bin = "pdftotext", required = false, hint = "install poppler-utils" },
  { bin = "tesseract",  required = false, hint = "install tesseract-ocr" },
  { python_module = "pdfplumber", hint = "pip install pdfplumber" },
})
```

Reports each entry via `:checkhealth` (`h_ok`/`h_warn`/`h_err`, `h_err` only
when `required = true`). `bin` is probed through `lib.nvim.core.has_exec`
(memoized); `python_module` shells out to `python -c "import <module>"`
against the first of `python3`/`python`/`py` found on `PATH`.

If you already have a parsed spec (see below), skip building the entry list
by hand:

```lua
local spec = require("lib.nvim.deps.spec")
local result = spec.load("docs/INSTALL.md")
require("lib.nvim.deps.health").from_tools(result.tools)
```

## `lib.nvim.deps.spec` — parse a plugin's `docs/INSTALL.md` / `docs/install.json`

Two authoring formats, same validated shape on the other side. Pick
whichever fits: Markdown for something a human reads on GitHub, JSON when
you want richer/longer content (multi-line `why`, extra metadata) or the
fastest possible parse (native `vim.json.decode`, no line-oriented subset
limits). See [`templates/deps/`](../../../../templates/deps/) for a
copy-paste starting point of each.

```lua
local spec = require("lib.nvim.deps.spec")

local result = spec.load("docs/INSTALL.md")   -- or docs/install.json
-- result.tools  : Lib.Deps.Tool[]  (bin, required, why, see?, pkg)
-- result.errors : Lib.Deps.Error[] (validation problems, if any — empty on a clean parse)

for _, err in ipairs(result.errors) do
  vim.notify(("docs/INSTALL.md tool #%d (%s): %s"):format(err.index, err.field or "?", err.message))
end
```

`why` is a **required, non-empty** field on every tool entry — a block
missing it fails validation the same way a malformed `pkg` map would,
rather than silently shipping a nameless "tool missing" report. `bin` and
at least one `pkg` entry are required for the same reason. `required`
defaults to `false`; `see` is optional.

```lua
-- Locate another plugin's spec, manager-agnostic:
local path = spec.find("pdfport.nvim")   --> ".../pdfport.nvim/docs/install.json" (preferred if present)
                                          --> or ".../pdfport.nvim/docs/INSTALL.md"
                                          --> or nil if the plugin ships neither

spec.plugins()                            --> every plugin that ships a spec, sorted
```

### How `find` resolves (and why it needs two steps)

1. **`runtimepath`** — manager-agnostic: packer, vim-plug, mini.deps, a
   symlinked dev checkout, and every *loaded* lazy.nvim plugin.
2. **lazy.nvim's plugin registry**, consulted via `pcall` only if step 1
   missed and lazy.nvim is present.

Step 2 is not redundant: lazy.nvim puts a plugin on `runtimepath` only once
it actually loads. Measured against a real config while building this —
**120 plugins configured, 44 loaded at startup, 76 pending**, and all 76 of
those were resolvable through lazy's `dir` while being absent from
`runtimepath`. A runtimepath-only lookup would therefore have silently
failed for the majority of a lazy-loading user's plugins, and "silently" is
the problem: a spec that can't be found looks exactly like a plugin that
ships none.

### `docs/INSTALL.md` format

Normal Markdown prose, with zero or more ` ```install-tool ` fenced blocks.
Each block's body is decoded with `lib.lua.yaml.simple_parse` — that
module's minimal YAML subset (no anchors, no flow style, no `|`/`>` block
scalars), so keep `why` to one line.

````markdown
```install-tool
bin: pdftotext
required: false
why: "Enables the fast plain-text extraction backend, no Python env needed."
pkg:
  apt: poppler-utils
  brew: poppler
  pacman: poppler
```
````

### `docs/install.json` format

```json
{
  "tools": [
    {
      "bin": "pdftotext",
      "required": false,
      "why": "Enables the fast plain-text extraction backend, no Python env needed.",
      "pkg": { "apt": "poppler-utils", "brew": "poppler", "pacman": "poppler" }
    }
  ]
}
```

## `lib.nvim.deps.health.report_for` — the `:checkhealth` hook

The one-line addition a plugin's own `health.lua` makes instead of
re-listing its tools a second time by hand:

```lua
-- inside your plugin's health.lua, in M.check():
require("lib.nvim.deps.health").report_for("pdfport.nvim")
```

Locates and parses the plugin's own spec, reports each tool the same way
`from_tools` does, and adds one line pointing at `:Lib deps show
<plugin>` for the fuller report. Silently does nothing if the plugin ships
no spec — a `:checkhealth` section for a plugin that declares nothing
shouldn't print anything.

## `lib.nvim.deps.first_run` — "tell me on first install, not from the README"

The flow this exists for: install a plugin via lazy.nvim, restart Neovim,
and the *first* time that plugin's `setup()` runs, see a popup explaining
which tools it wants and why — instead of reading the README and copying
install commands by hand. Every subsequent restart, `:Lib deps show
<plugin>` is the ongoing way to see the same report.

```lua
-- inside your plugin's own setup(), typically near the end:
function M.setup(opts)
  ...
  require("lib.nvim.deps").show_once("pdfport.nvim")
end
```

`show_once` is a no-op after its first call for a given plugin name — the
"seen" state persists across restarts (`lib.nvim.cache.disk`, namespace
`lib.nvim.deps.first_run`), and past-tense-only: nothing here re-checks or
re-notifies later just because a tool that was present becomes missing.
It's also a no-op, but still marks the plugin as seen, when there's simply
nothing to show — no spec file, an empty spec, or (once shown) a spec whose
declared tools are all already present.

This is the one call in `lib.nvim.deps` reachable from a place that isn't a
`:Lib deps` command — deliberately safe to be, since the trigger is still
an explicit action by the consuming plugin (`setup()`), never `require`,
and the popup itself only ever *shows* — installing anything still goes
through the same `i`/confirm/terminal path as `:Lib deps show` always has.

`:Lib deps reset-first-run [plugin]` clears the "seen" state (one plugin,
or every plugin with no argument) — mainly useful for testing this exact
flow without reinstalling the plugin.

### Opting out

Set either of these — anywhere in your own config, no
`require("lib.nvim.deps")` call needed:

```lua
vim.g.lib_nvim_deps_disable_first_run = true              -- every plugin, everywhere
vim.g.lib_nvim_deps_disabled_plugins = { "gopath.nvim" }   -- just these
```

**Where** matters less than it might seem: `vim.g` is a plain global, read
fresh on every `show_once` call, so it works no matter when or where it's
set relative to the plugin that calls `show_once` — the top of `init.lua`,
inside that plugin's own lazy.nvim `config = function() ... end`, anywhere.
This is deliberate: a user who installed, say, `gopath.nvim` alone (with
`lib.nvim` pulled in only as its transitive dependency) has no `lib.nvim`
config block of their own to put a `setup({ ... })` option into — a
`vim.g` toggle needs no such block to exist. Both variables are also worth
mentioning explicitly in **every consuming plugin's own README**, next to
its `docs/install.json` blurb — that's where a user who only installed
*that one plugin* will actually be looking when they want to turn the
popup off, not this file.

Neither variable is retroactive: it stops **future** `show_once` calls, it
does not mark anything as already-seen — so removing the opt-out later
picks up exactly where it would have without one, rather than having
silently consumed the "first run" while disabled.

**Future direction, not yet built:** a plugin could additionally expose
its *own* `setup({ deps_popup = false })`-style option that internally sets
the per-plugin `vim.g` entry (or simply skips its own `show_once` call) —
that would put the toggle in the one place a user is even more likely to
look first (that plugin's own `setup()` call) and matches how other
opt-in/opt-out flags already work across this ecosystem (e.g.
`lib.nvim_usrcmds`' `deps = true/false`). Deliberately not retrofitted into
every consuming plugin right now — the `vim.g` toggle already covers the
need with zero per-plugin code, and adding a redundant second knob to each
plugin's config schema is a cost worth paying only if the `vim.g` form
turns out not to be discoverable enough in practice.

## `lib.nvim.deps.pm` — package managers

```lua
local pm = require("lib.nvim.deps.pm")

pm.detect()      --> the manager to use here, or nil
pm.available()   --> every manager present, in this OS's preference order
pm.get("apt")    --> a manager definition by id, installed or not

pm.commands(pm.get("brew"), { "poppler", "tesseract" })
--> { { "brew", "install", "poppler", "tesseract" } }
pm.render({ "brew", "install", "poppler" })   --> "brew install poppler"
```

Known ids (the same keys a tool's `pkg` map uses): `apt`, `dnf`, `pacman`,
`zypper`, `apk`, `brew`, `winget`, `scoop`, `choco`. Preference order is
per-OS; WSL is treated as plain Linux, since inside WSL the distro's own
manager is the right answer.

`commands` returns a **list** of argv lists, not one: `winget` can't take
several packages per invocation (extra tokens become query terms), so it
gets one command per package while everything else gets one combined
command. Two deliberate omissions:

- **No `-y`/`--noconfirm`.** The package manager's own confirmation prompt
  is kept. The user runs this in a visible terminal anyway; seeing what apt
  is about to pull in beats suppressing it for tidiness.
- **No elevation logic beyond a `sudo` prefix** (added only when the manager
  needs root, the process isn't already root, and `sudo` is on PATH). On
  Windows, elevation is the manager's own business.

## `lib.nvim.deps.install` — plan and handoff

```lua
local install = require("lib.nvim.deps.install")

local plan = install.plan(result.tools)
-- plan.manager / present / missing / installable / unsupported / packages / commands

install.run(plan)   -- asks, then opens a terminal with the command typed, not submitted
```

`plan()` is pure — it probes PATH and detects the package manager, and
returns what *would* happen. `installable` vs. `unsupported` splits the
missing tools by whether this host's manager has a declared package name for
them, so a tool that simply has no `brew` entry is reported rather than
quietly dropped from the command.

`run()` refuses (returning `false`, with a notification) when there's no
package manager, nothing missing, or nothing installable — it only ever
opens a terminal when there is a real command to hand over.

## `lib.nvim.deps.view` — the report, and installing from it

```lua
local view = require("lib.nvim.deps.view")

view.lines("pdfport.nvim", result)         --> string[]  (pure, testable)
view.show("pdfport.nvim", result)          --> popup (kit.viewer) or a scratch split fallback
view.render("pdfport.nvim", result, opts, ui)  --> { lines, line_tools } — the overlay `show` builds on
```

Missing-and-required sorts first, then merely-missing, then present — the
reason to open this view is to find what isn't there. A `why` under 20
characters gets a visible nudge: the parser can enforce that `why` exists,
but not that it says anything useful, so that judgement is surfaced where a
plugin author will see it rather than pretended to be validation.

`show()` opens a `lib.nvim.ui.kit` `viewer` popup when kit is installed
(soft dependency — falls back to a plain read-only scratch split,
`view.show_split`, otherwise), with three keymaps:

| Key | Effect |
|---|---|
| `i` | Install the tool under the cursor |
| `<CR>` | Expand/collapse that tool's install output |
| `I` | Install everything missing |
| `q` / `<Esc>` | Close |

`i` does not always run inline. A package manager that needs root
(`pm.needs_terminal`) has no interactive stdin to answer a `sudo` password
prompt from a plain backgrounded job, so that case still confirms and hands
off to a real terminal via `deps.install.run` — the same safety rule as the
bulk install, just reached from a different key. Only managers that don't
need elevation (brew, scoop, most winget) install inline, streaming
stdout/stderr into the popup live via `lib.nvim.cross.uv.spawn_stream`, and
flip that tool's line from `[missing]` to `[ok]` the moment the install
finishes.
