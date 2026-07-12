# `lib.nvim.ui.kit` — User Guide

A themed, composable UI toolkit for Neovim plugins. Pick a preset once and every
popup is visually coordinated; or override colors/borders per call. Everything
is cross-platform (pure `nvim_open_win` + highlights).

- Design rationale: [UI-KIT-CONCEPT.md](ROADMAP/UI-KIT-CONCEPT.md)
- Vimhelp: `:help lib.nvim-kit`
- **Live playground:** `:KitPreview` (see [§6](#6-live-preview-playground))

## Contents
1. [Getting the module](#1-getting-the-module)
2. [Quick start](#2-quick-start)
3. [Themes & presets](#3-themes--presets)
4. [Components](#4-components)
5. [Layouts & templates](#5-layouts--templates)
6. [Live preview playground](#6-live-preview-playground)
7. [Highlight groups](#7-highlight-groups)

---

## 1. Getting the module

```lua
local kit = require("lib.nvim.ui.kit")
-- or via the aggregator:  require("lib").kit
```

Optionally configure once (registers presets and installs `:KitPreview`):

```lua
require("lib.nvim.ui.kit").setup({
  default = "rounded",          -- active preset when a call passes no theme
  presets = {                   -- your own named presets
    myplugin = { border = "double", hl = { accent = "WarningMsg" } },
  },
})
```

## 2. Quick start

```lua
kit.note({ title = "Saved", message = "Wrote 3 files", timeout = 2000 })
kit.toast({ message = "background job done" })
kit.select({ selection = { "one", "two", "three" }, on_select = function(item, i) end })
kit.confirm({ question = "Delete 3 files?", on_answer = function(yes) end })
kit.input({ prompt = "New name", default = "x", on_submit = function(text) end })
```

Every component also works through the one front door, `kit.popup{ type = … }`:

```lua
kit.popup({ type = "select", selection = { "a", "b" }, on_select = fn })
```

## 3. Themes & presets

A **theme** is a table of tokens (border, padding, zindex, title position, and
semantic highlight groups). Built-in **presets** differ mainly in border:

| Preset      | Border                                   |
| ----------- | ---------------------------------------- |
| `minimal`   | none                                     |
| `rounded`   | rounded (default)                        |
| `solid`     | single                                   |
| `double`    | double                                   |
| `ascii`     | ASCII glyphs (terminals w/o good Unicode) |

Anywhere a component takes a `theme`, you can pass:

```lua
kit.note({ message = "…", theme = "double" })                       -- a preset name
kit.note({ message = "…", theme = { hl = { accent = "WarningMsg" } } }) -- an override table
kit.note({ message = "…" })                                          -- nil → active default
```

Highlights **link to standard groups** by default (`NormalFloat`, `FloatBorder`,
`FloatTitle`, `PmenuSel`, `Special`, `Comment`, `DiagnosticError`), so the look
is correct in any colorscheme. Override any of the seven semantic keys:
`normal`, `border`, `title`, `selection`, `accent`, `muted`, `error`.

## 4. Components

| Type       | What it is | Sketch |
| ---------- | ---------- | ------ |
| `note`     | centered title + message float; optional `timeout` auto-dismiss | ↓ |
| `toast`    | ephemeral top-right message; stacks; never steals focus | ↓ |
| `input`    | single-line insert-mode prompt (`<CR>` submit, `<Esc>` cancel) | |
| `select`   | native themed list chooser (`j`/`k`, `<CR>`, `<Tab>` marks in multi) | |
| `prompt`   | ask: `answer_type = "confirm"` (yes/no → boolean) or `"text"` | |
| `confirm`  | horizontal-button dialog (`h`/`l` move, `<CR>` confirm) | ↓ |
| `menu`     | cursor-anchored action list (`{ label, action }`) | |
| `picker`   | interactive prompt + results + preview (see §5) | ↓ |
| `progress` | passthrough to [`lib.nvim.progress`](../lua/lib/nvim/progress/README.md) | |

**note** — `kit.note({ title, message, timeout? })`

![note](ROADMAP/assets/ui-kit/note.svg)

**toast** — `kit.toast({ message, timeout? })`

![toast](ROADMAP/assets/ui-kit/toast.svg)

**confirm** — `kit.confirm({ question, choices?, on_answer })`. Default
`Yes`/`No` yields a boolean; a custom `choices` list yields the chosen string
(cancel → `nil`). `h`/`l`/arrows move focus, `<CR>` confirms, `<Esc>`/`q`
cancels.

![confirm](ROADMAP/assets/ui-kit/confirm-buttons.svg)

```lua
kit.confirm({ question = "Pick", choices = { "Keep", "Discard", "Cancel" },
              on_answer = function(choice) end })
```

## 5. Layouts & templates

The **layout engine** turns a declarative region spec into aligned
`nvim_open_win` geometry for several coordinated floats — "windows that line up
perfectly", no gaps, recomputed on resize.

### The classic picker — the layout looks like this

`kit.layout.template("picker", …)` gives you a prompt (full width, top), a
result list (bottom-left, 40%) and a preview (bottom-right, 60%):

![picker layout](ROADMAP/assets/ui-kit/picker.svg)

```lua
-- Mount the template as-is, then fill the slots yourself:
local g = kit.layout.template("picker", { theme = "rounded" })
g.slots.results:set_lines(matches)
g.slots.preview:set_lines(preview_lines)
g.close()   -- closes every slot
```

### Custom arrangements

Compute geometry directly (pure, unit-testable) and mount it:

```lua
local geo = kit.layout.compute({
  width = 0.8, height = 0.8, gap = 0,
  rows = {
    { name = "prompt", height = 3 },                       -- fixed 3 rows
    { cols = {
        { name = "results", width = 0.4 },                 -- 40%
        { name = "preview", width = 0.6 },                 -- 60%
    }},
  },
})
-- geo.slots.prompt / .results / .preview → { row, col, width, height, relative }
```

Sizing per region: a fraction (`0.4` of the parent axis), a fixed integer
(`height = 3`), or `nil` (take the remainder). Copy `kit.layout.templates.picker.spec`
and tweak it, or write your own.

### Interactive picker (Telescope-style)

`kit.picker` makes the picker template live — an insert-mode prompt drives the
results:

```lua
local p = kit.picker({
  on_change = function(query) p.set_results(compute_matches(query)) end, -- debounced
  on_submit = function(idx, text) open(text) end,                        -- <CR>
})
-- <C-n>/<C-p> or arrows move the selection; <Esc> closes.
```

## 6. Live preview playground

Not sure how a theme will look? Run:

```vim
:KitPreview
```

(or `require("lib.nvim.ui.kit").preview()`). It opens a new tab split in two:

```
┌─────────────────────────┬──────────────────────────────┐
│ config (edit me)        │ preview (updates as you type) │
│                         │                               │
│ return {                │  Theme preview — border=double│
│   border = "double",    │  ╔══ note ══════════════════╗ │
│   hl = {                │  ║ A themed message float.   ║ │
│     accent = "…",       │  ╚═══════════════════════════╝ │
│   },                    │  ╔══ select ════════════════╗ │
│ }                       │  ║ selected item (current)   ║ │  ← KitSelection
│                         │  ║ marked item (multi)       ║ │  ← KitAccent
│                         │  … [ Yes ] «No» [ Cancel ] … │ │
└─────────────────────────┴──────────────────────────────┘
```

Edit the left buffer (a preset name or an override table); the right pane
re-renders instantly with your theme's borders and `KitSelection` / `KitAccent`
/ `KitTitle` / `KitMuted` colors. A broken config shows an error instead of
throwing. Press `q` to close.

## 7. Highlight groups

The kit materializes these global groups from the active theme (link targets in
parens); override them per theme via the `hl` keys:

| Group          | Default link       | Used for               |
| -------------- | ------------------ | ---------------------- |
| `KitNormal`    | `NormalFloat`      | body / background      |
| `KitBorder`    | `FloatBorder`      | borders                |
| `KitTitle`     | `FloatTitle`       | titles                 |
| `KitSelection` | `PmenuSel`         | current item / focused button |
| `KitAccent`    | `Special`          | marked items, accents  |
| `KitMuted`     | `Comment`          | hints / secondary text |
| `KitError`     | `DiagnosticError`  | errors                 |
