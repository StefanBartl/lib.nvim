# UI kit

`lib.nvim.ui.kit` — a themed, composable UI toolkit built in layers on top
of `lib.nvim.window` (`make_scratch`, `nice_quit`) and `lib.nvim.ui.hl`.
Nothing shells out, so every component is cross-platform. Pick a preset once
and every popup a plugin shows is visually coordinated instead of each
plugin inventing its own float styling.

## Theme and preset engine

A theme is a token table (border, padding, zindex, title position, dims,
highlight links). Built-in presets differ mainly in border strength, and
every one links to standard highlight groups (`NormalFloat`, `FloatBorder`,
`FloatTitle`, `PmenuSel`, …) so the default look is correct in any
colorscheme without per-plugin overrides.

- **Module:** `lib.nvim.ui.kit.theme` (`resolve`, `materialize`, `setup`,
  `presets`, `default`)
- **Config:** `require("lib.nvim.ui.kit").setup({ default = "rounded",
  presets = { myproject = { border = "double" } } })`
- **Usercmds:** `:KitPreview` (live theme playground)

Built-ins: `minimal` (no border), `rounded` (default), `solid`, `double`,
`ascii` (glyph border for terminals without good Unicode). A theme argument
anywhere one is accepted is a preset name, a partial override table
(deep-merged over the active default), or `nil`.

## Surface primitive

One themed float plus a lifecycle handle — the building block every
higher-level component (`note`, `toast`, `input`, `select`, …) is built on.

- **Module:** `lib.nvim.ui.kit.surface` (`open`)

```lua
local s = kit.surface.open({ lines = { "hi" }, theme = "double", title = "X" })
s:set_lines({ "new", "content" }); s:set_title("Y"); s:focus(); s:close()
```

## Popup component dispatch

`kit.popup(opts)` dispatches on `opts.type`, with convenience aliases
(`kit.note`, `kit.toast`, `kit.input`, `kit.select`, `kit.prompt`, …) for
every component. A not-yet-built type warns with its planned phase instead
of erroring.

- **Module:** `lib.nvim.ui.kit` (`popup`, and per-type aliases)

| Type | What it is |
| --- | --- |
| `note` | centered title + message float, optional auto-dismiss `timeout` |
| `viewer` | read-only, auto-sized info panel — closes on `q`/`<Esc>` or the moment focus leaves; the "show some info, dismiss it" float this replaced 6+ hand-rolled copies of |
| `toast` | ephemeral top-right message, stacks, never steals focus |
| `input` | single-line insert-mode prompt, `<CR>` submits, `<Esc>` cancels |
| `live_input` | `input` plus debounced `on_change(query)` as the user types |
| `form` | sequential multi-field prompt collected into one keyed table |
| `select` | native themed list chooser (single/multi) |
| `prompt` | ask: `confirm` (yes/no) or `text` |
| `confirm` | button dialog, `h`/`l`/arrows move, mouse-clickable |
| `menu` | cursor-anchored action list |
| `picker` | interactive Telescope-style prompt + results + preview |
| `progress` | passthrough to `lib.nvim.progress` |

## Input variants: secret masking and file completion

Two `vim.fn.input`/`vim.fn.inputsecret` replacements built into the same
`input` component rather than separate widgets.

- **Module:** `lib.nvim.ui.kit.input`

`secret = true` masks each typed character behind `opts.mask` (default
`"*"`) via `conceal`, re-derived from the buffer's real content on every
edit (paste, backspace, mid-line insert all just work) — the underlying
buffer holds the real text for `on_submit` to read, but nothing is ever
echoed, undo is disabled (`undolevels = -1`), and the buffer is never
written to disk and is wiped the moment the float closes.

`completion = "file"` (or any `getcompletion()` type name) wires `<Tab>` to
Neovim's real completion popup via `vim.fn.complete()`, so `<C-n>`/`<C-p>`
cycle it normally; while the popup is open `<Tab>`/`<S-Tab>` advance/retreat
the selection instead of re-triggering, and `<CR>` accepts the highlighted
candidate rather than submitting (a second `<CR>` submits).

## Multi-field forms

Chains `kit.input` prompts field-by-field into one keyed result table — the
"several `vim.fn.input` calls in a row" pattern several plugins had
duplicated (an Image/Name/Ports/Volumes/Env chain for a container-launch
form, for instance).

- **Module:** `lib.nvim.ui.kit.form`

```lua
kit.form({
  fields = {
    { name = "image", label = "Image", required = true },  -- <Esc> here aborts the form
    { name = "name", label = "Name" },                       -- <Esc> here skips
  },
  on_submit = function(values) end,
  on_cancel = function() end,  -- only fires if a required field was <Esc>-ed
})
```

## Button-confirm dialog

A horizontal-button question dialog, distinct from the yes/no `prompt`
component — for a choice among more than two named options, or when a
mouse-clickable target matters.

- **Module:** `lib.nvim.ui.kit.confirm`

```lua
kit.confirm({ question = "Pick", choices = { "Keep", "Discard", "Cancel" },
              on_answer = function(choice) end })
```

`h`/`l`/arrows/`<Tab>` move focus, `<CR>` confirms, `<Esc>`/`q` cancels. A
left click on a button focuses *and* confirms it in one action; clicking
blank space inside the dialog is a no-op everywhere in the kit — nothing
dismisses on an empty-space click.

## Declarative multi-float layout engine

Turns a declarative region spec into aligned `nvim_open_win` geometry for
several coordinated floats at once — the "three windows that line up
perfectly" primitive a picker (prompt/results/preview) needs.

- **Module:** `lib.nvim.ui.kit.layout` (`compute`, `mount`, `template`)

```lua
local group = kit.layout.template("picker", { theme = "rounded" })
group.slots.results:set_lines(matches)
group.close()   -- closes every slot
```

`layout.compute` is pure (no I/O) for callers that want to mount the
geometry themselves.

## Interactive picker and compare view

Two components built on the layout engine: a full Telescope-style picker,
and a "pick two items, view them side by side" compare flow.

- **Module:** `lib.nvim.ui.kit.picker`, `lib.nvim.ui.kit.compare`

```lua
local p = kit.picker({
  on_change = function(query) p.set_results(compute_matches(query)) end,  -- debounced
  on_submit = function(idx, text) open(text) end,
})
```

`kit.picker({ prompt = "plain" })` falls back to a bare layout template
whose prompt slot the caller wires themselves. `compare` walks
SEARCH → MARKED → COMPARE, letting a user pick exactly two items from one
picker and see them side by side.

## Synchronous bridge for async components

`kit.input`/`kit.form`/`kit.live_input`/`kit.picker` are inherently
async — `on_submit`/`on_cancel` fire later. `kit.sync` bridges one of them
back to a plain return value via `vim.wait()`, for a call chain built
around a blocking `vim.fn.input()` that can't easily be recast to callback
style.

- **Module:** `lib.nvim.ui.kit.sync` (`open`, exposed as `kit.sync`)

```lua
local values, cancelled, timed_out = kit.sync(kit.form, { fields = { ... } })
```

Only safe from a normal call stack (a command handler, a keymap callback) —
never from a fast-event/libuv callback context, the same restriction
`vim.wait()` itself has. Default timeout 10 minutes (a safety net, not the
expected path).
