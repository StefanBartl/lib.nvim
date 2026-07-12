# Task: native select chooser + interactive picker prompt (UI kit, Phase 3 finish)

> **Status: DONE.** Part A (native `lib.nvim.ui.kit.chooser`, `kit.select`
> rewire, hover_select shim) and Part B (interactive `kit.picker`) are both
> implemented, tested, and pushed. Phase 3 is complete; the notes below are the
> original task spec, kept for reference.
>
> Type: **implementation task** (not a concept — the design is settled).
> Parent design: [UI-KIT-CONCEPT.md](UI-KIT-CONCEPT.md) (§7a templates, §8
> components, §10 hover_select absorption). Everything cross-platform.

## Context / where we are

`lib.nvim.ui.kit` has shipped:

- Phase 1 — theme/preset engine, `surface` primitive, `note`.
- Phase 2 — `toast`, `input`, `select` (currently **delegates** to
  `lib.nvim.ui.hover_select`), `prompt` (confirm/text).
- Phase 3 (part) — layout engine (`kit.layout.compute`/`mount`) + template
  registry with the `picker` template (plain slots).

Two Phase-3 items remain, both in this task:

- **A. Native `select` chooser** — a themed list chooser built inside the kit,
  replacing the Phase-2 delegation and beginning the hover_select absorption
  (§10 steps 2–3).
- **B. Interactive picker prompt** — make the `picker` template's `prompt` slot
  drive the `results` slot as the user types (the "works like Telescope out of
  the box" behavior from §7a).

Do **A first** (B reuses the chooser's selection movement).

---

## A. Native select chooser

### Goal
A themed chooser living at `lua/lib/nvim/ui/kit/chooser.lua` (name flexible),
used by `kit.select` / `kit.popup({ type = "select" })`. It must be a
**superset of `Lib.HoverSelect.Options`** so the eventual `hover_select` shim
(step 3 below) is a pure mapping with **no feature gaps**.

### Must reuse / match (from the existing hover_select)
Read these before starting — the semantics must match so external call sites
behave identically after absorption:

- `lua/lib/nvim/ui/hover_select/init.lua` — `open`/`close`/`is_open`, state
  shape, single vs multi-select, `on_select(item, idx)` /
  `on_select(items, indices)` callback contract.
- `lua/lib/nvim/ui/hover_select/navigation.lua` — `j`/`k`/arrows move, `<CR>`
  selects, `<Esc>`/`q` close, `h`/`l` blocked; multi-select `<Tab>` toggle.
- `lua/lib/nvim/ui/hover_select/highlight.lua` — cursorline + multi-select mark
  highlighting (the kit version themes these via the theme's `selection`/
  `accent` groups instead of hard-coded colors).
- `lua/lib/nvim/ui/hover_select/window.lua` / `buffer.lua` — auto-width /
  dimension logic.

### Build on the kit
- Render into a `kit.surface` (theme applied, `selection` highlight = the
  theme's `KitSelection` group; multi-select marks = `KitAccent`).
- Navigation keymaps via `lib.nvim.map`; buffer-local, `nowait`.
- Return the surface handle plus the same callback contract as hover_select.

### Superset options (union of hover_select + kit)
`items`, `on_select`, `multi_select`, `title`, `relative`, `width`, `height`,
`auto_width`, plus `theme` (kit addition). Preserve hover_select's
`use_tab_navigation` deprecation shim so nothing breaks.

### Wire-up
- Point `lua/lib/nvim/ui/kit/select.lua` at the native chooser (drop the
  `hover_select` delegation).
- `kit.prompt` confirm/list already calls `kit.select` → gets the native
  chooser for free.

### hover_select absorption (§10 steps 2–3) — do in this task
1. Native chooser built (above) = **step 2**.
2. **Step 3 (shim):** reimplement `lua/lib/nvim/ui/hover_select/init.lua` as a
   thin adapter that maps `Lib.HoverSelect.Options` → the kit chooser and
   forwards the callback. Keep the exact public signature
   (`open`/`close`/`is_open`) so the ~10 external call sites are untouched.
   Delete the now-unused `hover_select/{buffer,window,navigation,highlight}.lua`
   (logic lives in the kit). Keep `hover_select/@types` for the public option
   class, or re-point it.
3. Leave call-site migration + eventual removal as a **follow-up** (step 4) —
   out of scope here; just make the shim correct.

### Acceptance
- New `docs/TESTS/*_spec.lua` (or extend `ui_kit_spec.lua`): chooser opens
  themed, single-select returns `(item, idx)`, multi-select returns
  `(items, indices)`, `is_open`/`close` work, `KitSelection` used.
- A hover_select shim test: `require("lib.nvim.ui.hover_select").open(...)` still
  returns the same values / fires the same callback as before (regression
  guard for the ~10 consumers).
- `nvim --headless -u NONE -l docs/TESTS/run.lua` → `LIB_TESTS_OK`; stylua clean;
  `:checkhealth lib` green.

---

## B. Interactive picker prompt

### Goal
`kit.layout.template("picker", opts)` mounts a prompt that behaves like a picker
prompt out of the box, driving the `results` slot.

### Behavior (from §7a)
- `opts.prompt = "picker"` (default for the picker template): the `prompt` slot
  is an insert-mode input (reuse `lua/lib/nvim/ui/kit/input.lua` patterns) that
  **debounces** keystrokes and calls `opts.on_change(query)`; the caller returns
  / sets the result lines. `<CR>` → `opts.on_submit(selected)`; `<C-n>`/`<C-p>`
  and arrows move the selection **in the results slot** (reuse the chooser's
  movement from part A); `<Esc>` closes the whole group.
- `opts.prompt = "plain"`: prompt slot is a bare `surface` the caller wires
  itself (already the current behavior — keep it).

### Notes
- Debounce with `vim.uv` timer (cross-platform; see `lib.nvim.cross.uv`) or
  `vim.defer_fn`.
- The results slot is a chooser-in-a-fixed-window (no its own border movement —
  selection highlight moves within the slot). Factor the chooser's
  selection-movement so both the standalone chooser (A) and the picker results
  slot (B) share it.
- `kit.picker` convenience wrapper (optional) = `layout.template("picker", …)`
  with sensible defaults.

### Acceptance
- Spec: mounting the picker template with `on_change`/`on_submit`, feeding a
  query updates the results slot; moving selection + `<CR>` calls `on_submit`
  with the highlighted item. (Headless: drive via the exposed movement/submit
  functions rather than real keystrokes where needed.)
- Update `docs/ROADMAP/UI-KIT-CONCEPT.md` §13 status → Phase 3 ✅, and the
  `picker.svg` sketch can be replaced by a real screenshot once it runs.

---

## Registration checklist (per repo convention)
- `lua/lib/nvim/ui/kit/@types/init.lua` — types for the chooser + picker opts.
- No new aggregator key needed (all under `kit`), but update
  `doc/lib.nvim-kit.txt`, `lua/lib/nvim/ui/kit/README.md`, and the concept
  status.
- Keep `:checkhealth lib` probe (`lib.nvim.ui.kit`) passing.

## Definition of done
- Native chooser is the engine for `kit.select`; hover_select is a passing shim
  over it (no external breakage).
- Picker template prompt is interactive (`"picker"`) or plain (`"plain"`).
- Tests green, stylua clean, docs + concept status updated, committed & pushed.
