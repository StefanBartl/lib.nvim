# `lib.nvim.ui.kit`

A themed, composable UI toolkit. Pick a preset once and every popup is visually
coordinated, or override colors/borders per call. Built in layers on top of
[`lib.nvim.window`](../../window) (`make_scratch`, `nice_quit`) and
[`lib.nvim.ui.hl`](../hl) — nothing shells out, so it is cross-platform.

> **New here?** Read the [User Guide](../../../../../docs/GUIDE-ui-kit.md)
> (with layout sketches), run **`:KitPreview`** for a live theme playground,
> or see [docs/EXAMPLES](../../../../../docs/EXAMPLES) for one scenario per
> component (`kit-note.lua`, `kit-viewer.lua`, `kit-toast.lua`,
> `kit-input.lua`, `kit-form.lua`, `kit-select.lua`, `kit-prompt.lua`,
> `kit-confirm.lua`, `kit-menu.lua`, `kit-picker.lua`, `kit-layout.lua`).

> **Phases 1–2** (this release): theme/preset engine + `surface` primitive +
> components `note`, `toast`, `input`, `select` (delegates to hover_select) and
> `prompt` (confirm/text). The full design (layout engine, templates, native
> select chooser, button-confirm) lives in
> [`docs/ROADMAP/UI-KIT-CONCEPT.md`](../../../../../docs/ROADMAP/UI-KIT-CONCEPT.md).

## Themes & presets

A theme is a token table (border, padding, zindex, title_pos, dims, `hl`).
Built-in presets differ mainly in border strength:

| Preset      | Border    |
| ----------- | --------- |
| `minimal`   | none      |
| `rounded`   | rounded (default) |
| `solid`     | single    |
| `double`    | double    |
| `ascii`     | ASCII glyphs (terminals without good Unicode) |

Highlights link to standard groups (`NormalFloat` / `FloatBorder` /
`FloatTitle` / `PmenuSel` / …), so the default look is correct in any
colorscheme.

```lua
require("lib.nvim.ui.kit").setup({
  default = "rounded",
  presets = {
    myproject = { border = "double", hl = { title = "Title" } },
  },
})
```

A theme argument (anywhere one is accepted) is a preset name, a partial override
table (deep-merged over the active default), or `nil`.

## Surface

One themed float + a lifecycle handle:

```lua
local kit = require("lib.nvim.ui.kit")
local s = kit.surface.open({ lines = { "hi" }, theme = "double", title = "X" })
s:set_lines({ "new", "content" })
s:set_title("Y")
s:focus()
s:on_close(function() end)
s:close()
```

`open(opts)` accepts `lines`, `theme`, `title`, `title_pos`, `width`, `height`,
`relative`, `row`, `col`, `zindex`, `enter`, `focusable`, `nice_quit`,
`filetype`, `modifiable`, `wo`, `bo`. Returns the handle, or `nil` on failure.

## Components

`kit.popup(opts)` dispatches on `opts.type` (convenience aliases: `kit.note`,
`kit.toast`, `kit.input`, `kit.select`, `kit.prompt`). Not-yet-built types warn
with their planned phase.

```lua
kit.popup({ type = "note",  title = "Saved", message = "Wrote 3 files", timeout = 2000 })
kit.popup({ type = "viewer", title = "Node Info", lines = { "name: foo.lua", "size: 128 B" } })
kit.popup({ type = "toast", message = "background job done" })
kit.popup({ type = "input", prompt = "New name", default = "x", on_submit = function(t) end })
kit.popup({ type = "form", fields = { { name = "image", label = "Image", required = true } },
            on_submit = function(values) end })
kit.popup({ type = "select", message = "Pick", selection = { "a", "b" }, on_select = function(c, i) end })
kit.popup({ type = "prompt", question = "Delete?", answer_type = "confirm", on_answer = function(yes) end })
```

| Type     | What it is |
| -------- | ---------- |
| `note`   | centered title + message float; optional `timeout` (ms) auto-dismiss |
| `viewer` | read-only info panel; auto-sized to content; closes on q/`<Esc>` OR the moment focus leaves it — the "show some info, dismiss it" float duplicated 6+ times across consumer plugins before this existed |
| `toast`  | ephemeral top-right message; stacks; never steals focus; auto-dismiss |
| `input`  | single-line insert-mode prompt; `<CR>` submits, `<Esc>` cancels |
| `form`   | sequential multi-field prompt — chained `input`s collected into one keyed table; `<Esc>` skips an optional field, aborts on a `required` one |
| `select` | native themed list chooser (single/multi; `j`/`k`, `<CR>`, `<Tab>` mark) |
| `prompt` | ask: `answer_type = "confirm"` (yes/no → boolean) or `"text"` |
| `confirm` | button dialog — horizontal buttons, `h`/`l`/arrows move, `<CR>` confirm, `<Esc>` cancel |
| `menu`    | cursor-anchored action list — `{ label, action }` items; picking runs the action |
| `progress`| passthrough to [`lib.nvim.progress`](../../progress/README.md) (`:update`/`:finish`/`:cancel`) |

## Layout engine (Phase 3, partial)

Turn a declarative region spec into aligned `nvim_open_win` geometry for several
coordinated floats — the "three windows that line up perfectly" primitive.

```lua
-- ready-made picker template (prompt / results / preview):
local group = kit.layout.template("picker", { theme = "rounded" })
group.slots.results:set_lines(matches)
group.slots.preview:set_lines(preview_lines)
group.close()               -- closes every slot

-- or compute geometry yourself (pure, no I/O) and mount:
local geo = kit.layout.compute({
  width = 0.8, height = 0.8, gap = 0,
  rows = {
    { name = "prompt", height = 3 },
    { cols = { { name = "results", width = 0.4 }, { name = "preview", width = 0.6 } } },
  },
})
```

### Interactive picker

`kit.picker(opts)` turns the picker template into a working, Telescope-style
picker: an insert-mode prompt drives the results slot.

```lua
local p = kit.picker({
  on_change = function(query)          -- debounced as the user types
    p.set_results(compute_matches(query))
  end,
  on_submit = function(idx, text)      -- <CR> on the highlighted result
    open(text)
  end,
})
-- <C-n>/<C-p> or arrows move the selection; <Esc> closes.
-- p.query() / p.set_results(lines) / p.move(delta) / p.submit() / p.close()
```

`kit.picker({ prompt = "plain" })` falls back to a bare
`kit.layout.template("picker")` whose prompt slot you wire yourself.

### Button-confirm

`kit.confirm(opts)` (or `kit.popup({ type = "prompt", answer_type = "confirm",
layout = "buttons" })`) shows a question with a row of horizontal buttons.

```lua
kit.confirm({ question = "Delete 3 files?", on_answer = function(yes) end })     -- Yes/No -> boolean
kit.confirm({ question = "Pick", choices = { "Keep", "Discard", "Cancel" },
              on_answer = function(choice) end })                               -- custom -> string
```

`h`/`l`/arrows/`<Tab>` move focus (the focused button uses `KitSelection`),
`<CR>` confirms, `<Esc>`/`q` cancels (default → `false`, custom → `nil`). See
[assets/ui-kit/confirm-buttons.svg](../../../../../docs/ROADMAP/assets/ui-kit/confirm-buttons.svg).

### Form (multi-field)

`kit.form(opts)` chains `kit.input` prompts field-by-field into one keyed
result table — the "several `vim.fn.input`/`vim.ui.input` calls in a row"
pattern (e.g. sandbox.nvim's Image/Name/Ports/Volumes/Env chain).

```lua
kit.form({
  fields = {
    { name = "image", label = "Image", required = true },  -- <Esc> here aborts the form
    { name = "name", label = "Name" },                       -- <Esc> here skips (keeps default)
    { name = "ports", label = "Ports" },
  },
  on_submit = function(values) end,  -- { image = "...", name = "...", ports = "..." }
  on_cancel = function() end,        -- fires only if a `required` field was <Esc>-ed
})
```

Each field accepts the same options as `kit.input` (`default`, `theme`,
`width`, `relative`, `expand_env`), falling back to `opts.theme`/`opts.width`/
`opts.relative` when omitted.
