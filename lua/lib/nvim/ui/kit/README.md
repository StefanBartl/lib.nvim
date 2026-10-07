# `lib.nvim.ui.kit`

> **Migrated to `ui.nvim` (2026-09-14).** This module's canonical home is now
> [`ui.nvim`](https://github.com/StefanBartl/ui.nvim) (`lua/ui/kit/`,
> `require("ui.kit")`) — every one of this ecosystem's ~31 consumer plugins
> was moved over (see `ui.nvim`'s own
> [`PLAN-ui-kit-migration.md`](https://github.com/StefanBartl/ui.nvim) for
> the full history). No shim was built and no code here was deleted, so
> this copy still works standalone, but it no longer receives new
> features — those land in `ui.nvim` only. Do not build new callers
> against `lib.nvim.ui.kit`; require `ui.kit` from `ui.nvim` instead.
>
> **Bug fixes are not new features, and this copy does get them
> (2026-09-17).** "Frozen" drifted into "keeps known bugs": three fixes and
> a security note had landed in `ui.nvim` only, while the copy here — the
> one eleven of this library's own call sites actually run — still had a
> `WinClosed` augroup leaked per surface, a picker debounce timer that
> outlived its picker, and a submenu that shifted by its own height near
> the bottom of the screen. All three are ported.
>
> Nothing compared the two copies, which is why it went unnoticed for
> weeks. Something does now: `ui.nvim`'s `TESTS/kit_drift_spec.lua` diffs
> them in CI (it already checks this repository out at `ci-verified`) and
> fails naming the file. **A fix made in `ui.nvim` has to be mirrored
> here**, or this copy silently keeps the bug for every consumer above.
>
> **One feature was mirrored too (2026-10-07):** `kit.form`'s opt-in `back`
> navigation, with `kit.input`'s `on_back`/`buttons` and the `ui.kit.buttons`
> helper under it. The drift spec compares code, not intent, so a kit feature
> left on one side is a red CI run; the feature is off unless asked for, so
> this library's own call sites behave as before. Everything else above still
> holds: build new callers against `ui.nvim`.

A themed, composable UI toolkit. Pick a preset once and every popup is visually
coordinated, or override colors/borders per call. Built in layers on top of
[`lib.nvim.window`](../../window) (`make_scratch`, `nice_quit`) and
[`lib.nvim.ui.hl`](../hl) — nothing shells out, so it is cross-platform.

> **New here?** Read the [User Guide](../../../../../docs/GUIDE-ui-kit.md)
> (with layout sketches), run **`:KitPreview`** for a live theme playground,
> or see [docs/EXAMPLES](../../../../../docs/EXAMPLES) for one scenario per
> component (`kit-note.lua`, `kit-viewer.lua`, `kit-toast.lua`,
> `kit-input.lua`, `kit-live-input.lua`, `kit-form.lua`, `kit-select.lua`,
> `kit-prompt.lua`, `kit-confirm.lua`, `kit-menu.lua`, `kit-picker.lua`,
> `kit-layout.lua`, `kit-sync.lua`).

> **Phases 1–2** (this release): theme/preset engine + `surface` primitive +
> components `note`, `toast`, `input`, `select` (delegates to hover_select) and
> `prompt` (confirm/text). The layout engine, templates, native select chooser
> and button-confirm follow.

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
| `menu`      | rounded, but with a **coloured** frame (`Function`) — `kit.menu`'s default |

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
kit.popup({ type = "input", prompt = "Password", secret = true, on_submit = function(pw) end })
kit.popup({ type = "input", prompt = "Path", completion = "file", on_submit = function(p) end })
kit.popup({ type = "live_input", prompt = "Filter", on_change = function(query) end })
kit.popup({ type = "form", fields = { { name = "image", label = "Image", required = true } },
            on_submit = function(values) end })
kit.popup({ type = "sheet", fields = { { name = "image", label = "Image", required = true }, { name = "tag", label = "Tag" } },
            on_submit = function(values) end })
kit.popup({ type = "select", message = "Pick", selection = { "a", "b" }, on_select = function(c, i) end })
kit.popup({ type = "prompt", question = "Delete?", answer_type = "confirm", on_answer = function(yes) end })
```

| Type     | What it is |
| -------- | ---------- |
| `note`   | centered title + message float; optional `timeout` (ms) auto-dismiss |
| `viewer` | read-only info panel; auto-sized to content; closes on q/`<Esc>` OR the moment focus leaves it — the "show some info, dismiss it" float duplicated 6+ times across consumer plugins before this existed |
| `toast`  | ephemeral top-right message; stacks; never steals focus; auto-dismiss |
| `input`  | single-line insert-mode prompt; `<CR>` submits, `<Esc>` cancels; `secret = true` masks it as you type; `completion = "file"` (or any `getcompletion()` type) wires `<Tab>` to the native completion popup |
| `live_input` | like `input`, but also debounces keystrokes into `on_change(query)` as you type — for filter/search boxes |
| `form`   | sequential multi-field prompt — chained `input`s collected into one keyed table; `<Esc>` skips an optional field, aborts on a `required` one; `back = true` adds [back navigation](#form-multi-field) (`<BS>` on an empty field, `<S-Tab>`, a `[← Back] [Skip] [Next ↵]` button row, "(2/5)" in the title) |
| `sheet`  | every field of a form at once in ONE float — a labelled row each, inline validation (`required`, `validate`) shown under the field, `[ Submit ] [ Cancel ]` buttons; see [Sheet](#sheet-every-field-at-once) |
| `select` | native themed list chooser (single/multi; `j`/`k`, `<CR>`, `<Tab>` mark) |
| `prompt` | ask: `answer_type = "confirm"` (yes/no → boolean) or `"text"` |
| `confirm` | button dialog — horizontal buttons, `h`/`l`/arrows move, `<CR>` confirm, `<Esc>` cancel, left click confirms a button directly (the button row is `lib.nvim.ui.kit.buttons`, shared with the form's) |
| `menu`    | anchored action list — `{ label, action }` items; picking runs the action. Also renders [`lib.nvim.contextmenu`](../../contextmenu/README.md) tables (`name`/`cmd`, `{ name = "separator" }`, `rtxt`, `icon`, nested `items`) and takes `mouse = true` to anchor at the pointer. A row is a set of **fixed-width columns** measured across the whole level — icon, label, fly-out marker, `rtxt` — so entries line up whichever section they sit in; `icon` is a field, never a prefix on `label`. The marker follows the *label* column rather than the row, so it stays beside the list instead of against the frame, and the hint column keeps the right edge. Named groups (`contextmenu.heading`) are drawn as titled frames (`group_style` = `"box"` \| `"header"` \| `"plain"`; a menu that names nothing keeps the plain divider look). The block cursor is hidden while it is open, one left click picks, and a click or focus change elsewhere dismisses it (`hide_cursor` / `single_click` / `close_on_focus_lost` turn those off). A pick is acknowledged before it is acted on: the row lights up (`KitFlash`) for `flash_ms` (default 100) and the action follows, the way a button shows its press — the delay is the point, since a leaf action closes the menu and a flash painted at that moment would never be seen. A menu dismissed while a row is lit runs nothing (`flash_on_select = false` turns it off). Defaults to the `menu` preset, so the frame is coloured. Drilling into a submenu and walking back swap the list **inside the same window** — no flash, and the menu stays put |
| `progress`| passthrough to [`lib.nvim.progress`](../../progress/README.md) (`:update`/`:finish`/`:cancel`) |
| `compare` | pick two items out of one picker, then view them side by side — see [Compare](#compare-pick-two-view-side-by-side) below |

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

#### Item mode (a list of items with marks, highlights and a preview)

With `items` (or `format`) the results slot lists ITEMS instead of plain lines:

```lua
local p = kit.picker({
  items = tasks,
  key = function(t) return t.id end,            -- identity for marks and the cursor (default: the item itself)
  text = function(t) return t.title end,        -- what the prompt's words are matched against (default: item.text)
  format = function(t) return { { t.title, "Title" }, { " " .. t.status, "Comment" } } end,
  preview = function(t, surface) surface:set_lines(read_lines(t.path)) end,   -- follows the cursor item
  selectable = function(t) return not t.heading end,   -- rows that cannot be submitted, marked or rested on (headings)
  keys = { ["<M-d>"] = function(h) finish(h.marked()) end },                 -- lhs -> function(handle), in the prompt
  title = "Tasks", results_width = 0.6,
  on_submit = function(idx, line, item) open(item) end,
  on_close = function() end,
})
-- <Tab> marks and moves down. p.current() / p.marked() / p.set_items(items, { cursor_key?, keep_marks? }) /
-- p.set_title(t) / p.is_closed()
```

The words typed in the prompt filter the list (every word must occur, any case); an empty result stays open.
`set_items` keeps the cursor on its item and the marks of items that are still there.

`kit.picker({ prompt = "plain" })` falls back to a bare
`kit.layout.template("picker")` whose prompt slot you wire yourself.

### Compare (pick two, view side by side)

`kit.compare(opts)` picks two items out of one picker, then shows both full
height, side by side — motivated by images.nvim's "browse, pick two, view
next to each other", but not image-specific: `render(item, surface)` is the
only contract, so a text diff or anything else that can paint into a
`kit.surface` works the same way.

```lua
local handle = kit.compare({
  items = candidates,
  render = function(item, surface)     -- called for the live preview AND
    surface:set_lines(read_lines(item)) -- both COMPARE panes
  end,
  on_compare = function(a, b)          -- fires once, before either COMPARE
    -- both picks known here, before either render() call for COMPARE --
    -- e.g. scale two images relative to each other instead of each to its
    -- own pane
  end,
  on_close = function(a, b) end,       -- b is nil on an aborted pick
})
```

Three states, entered in order: **SEARCH** (prompt + results + a live
preview that follows the selection) → **MARKED** (`mark_key`, default
`<M-c>`, or `<CR>`, freezes the current item; the live preview keeps
following the rest of the search) → **COMPARE** (`<CR>` again: both picks
full-height, side by side; `q`/`<Esc>` on either pane closes the whole
thing). `<CR>` does double duty on purpose — it reads as "confirm whichever
pick this is" rather than needing a second dedicated key.

`kit.chooser` is the low-level native chooser `kit.select` (and `compare`'s
own SEARCH state) delegates to — reach for it directly only when a caller
needs `current_item()`/`current_index()`/`move()` outside of `on_select`,
e.g. extra keymaps that read the highlighted item without submitting or
closing. One active instance at a time, shared with `kit.select`.

### Button-confirm

`kit.confirm(opts)` (or `kit.popup({ type = "prompt", answer_type = "confirm",
layout = "buttons" })`) shows a question with a row of horizontal buttons.

```lua
kit.confirm({ question = "Delete 3 files?", on_answer = function(yes) end })     -- Yes/No -> boolean
kit.confirm({ question = "Pick", choices = { "Keep", "Discard", "Cancel" },
              on_answer = function(choice) end })                               -- custom -> string
```

`h`/`l`/arrows/`<Tab>` move focus (the focused button uses `KitSelection`),
`<CR>` confirms, `<Esc>`/`q` cancels (default → `false`, custom → `nil`).

**Mouse:** a left click on a button focuses *and* confirms it in one action
(needs `:set mouse=a`, as any mouse interaction does). Clicking blank space
inside the dialog is a no-op — it does not cancel, matching the rest of the
kit, where clicking empty space never dismisses a surface. Hit-testing uses
`getmousepos()` against the per-button ranges the focus highlight already
tracks, so the click target is exactly the visible `[ Label ]` box.

The layout, the focus highlight and the hit-test live in
`lib.nvim.ui.kit.buttons` — a small stateless helper (`layout`, `paint`, `hit`,
`wrap`, `row_width`) that the button row under a [`kit.form`](#form-multi-field)
field uses as well, so a click lands on exactly the box that is drawn in both
places.

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

**Back navigation (`back = true`, opt-in; mirrored from `ui.nvim`).** Off by
default — a form without it is exactly the chain above. With it, `<BS>` on an
**empty** field, `<S-Tab>` or `<C-p>` (or the `[← Back]` button) reopen the
field before with its previous answer as the editable text; a field left
half-typed keeps its text for when the user comes back, so nothing is lost
going back and forth; `<Esc>` keeps its meaning on every field; the first
field has no back; the title reads `Label (2/5)`. A button row sits under the
field — `[← Back]`, `[Skip]` (not on a `required` field) and `[Next ↵]`
(`[Done ↵]` on the last) — a left click presses one, and `<Down>`/`<Tab>` move
the focus onto the row (`h`/`l`/arrows/`<Tab>` move it, `<CR>` presses,
`<Up>`/`k`/`i`/`a` return to the field). A `<BS>` held down stops at the empty
field (a `<BS>` less than 300 ms after the previous one is the key repeating,
not a press); a long answer that scrolls the field sideways keeps the row in
view, and a paste with a newline stays one line. Underneath, `kit.input` takes
`on_back = function(line) end` and `buttons = { { id = "back" | "skip" |
"submit", label = "…" }, … }`. A form that is itself one step of a longer flow
can also pass `on_back = function(values) end`: the first field then has a back
too, which closes the form and hands the answers so far on (neither `on_submit`
nor `on_cancel` fires). The full description is in `ui.nvim`'s
`lua/ui/kit/README.md`.

### Sheet (every field at once)

`kit.sheet(opts)` (or `kit.popup({ type = "sheet", ... })`) is the other shape
of a form: not one prompt per field in a row, but ONE float that shows every
field at once, a row each with its label. Use it when the answers belong
together and the person should see — and be able to fix — all of them before
committing; `kit.form` stays the right tool for a short chain of questions.
Same callbacks (`on_submit(values)` / `on_cancel()`), same keyed result table,
so `kit.sync(kit.sheet, opts)` works too.

```lua
kit.sheet({
  title = "New case",
  fields = {
    { name = "number", label = "Case number", required = true, live = true,
      validate = function(v)
        if v:match("^%d+$") then return true end
        return false, "digits only"            -- the message shows under the field
      end },
    { name = "area", label = "Area", kind = "select", choices = { "EMEA", "APAC" } },
    { name = "title", label = "Title" },
    { name = "token", label = "Token", secret = true },
  },
  submit_label = "Create", cancel_label = "Abort",     -- default "Submit" / "Cancel"
  on_submit = function(values) end,  -- { number = "...", area = "EMEA", title = "...", token = "..." }
  on_cancel = function() end,
})
```

```text
╭────────────────────────── New case ──────────────────────────╮
│Case number* 12x                                              │
│             ✗ digits only                                    │
│Area         EMEA   ◂ ▸                                       │
│Title        Printer on fire                                  │
│Token        ********                                         │
│                                                              │
│                   [ Create ]  [ Abort ]                      │
╰──────────────────────────────────────────────────────────────╯
```

**Fields.** `{ name, label?, kind?, default?, required?, validate?, live?,
expand_env?, completion?, secret?, mask?, choices? }`:

- `kind = "text"` (default) is an editable line like [`kit.input`](#components):
  `default`, `expand_env`, `completion` and `secret` behave the same. The
  field's row opens in Insert mode.
- `kind = "select"` with `choices` (a list of strings) is a fixed choice shown
  with `◂ ▸`: `h`/`l` (or the arrows) cycle it, `<CR>`/`<Space>` open
  `kit.select` over the choices and a pick moves on to the next field.
  `default` names the choice shown first.

**Validation, next to the field.**

- `required = true` rejects a blank value ("required", or `opts.required_message`).
- `validate(value) -> ok, err` rejects when `ok` is falsy, showing `err`
  ("invalid" without one) as red text (`KitError`) in a line under the field. It
  is not called for an empty optional field, so it never has to handle `""`;
  `value` is what `on_submit` will get (after `expand_env`); a validator that
  raises is a rejection with the error as its message.
- A field is checked when the user **leaves** it and on **submit**. A field that
  shows an error is checked again on every edit, so the message goes away the
  moment the value is right; `live = true` checks a field on every edit from the
  start.
- Submit is blocked while any field fails, and the focus jumps to the first
  invalid one. The window is resized to what is shown (a row per message), so
  the sheet grows and shrinks, staying centered.

**Keys** (the same in Insert mode on a text row and in Normal mode elsewhere):

| Key | Does |
| --- | --- |
| `<Tab>` / `<S-Tab>` | next / previous field, then the two buttons, wrapping |
| `<Down>` / `<Up>` (`j` / `k` in Normal mode) | the same without wrapping |
| `<CR>` | next field; on the last field it presses the Submit button; on a select it opens the chooser; on a button it presses it |
| `<Esc>` | cancel the whole sheet, from anywhere |
| left click | focus the field under the pointer (cursor at the click), or press the button (needs `:set mouse=a`) |
| `h` / `l`, `<Space>` | on the button row: move along / press; on a select: cycle / open the chooser |

On a field with `completion`, `<Tab>` is the completion key (as in `kit.input`)
and `<S-Tab>` still goes back unless a popup is open; move on with `<Down>`/`<CR>`.

**Drawn how.** The buffer holds only the values, one per line (then a blank line
and the buttons); the labels are the window's `'statuscolumn'`. So an edit can
never touch a label, the cursor cannot land on one, and a long value wraps under
the value column. The button row is `lib.nvim.ui.kit.buttons`, shared with `kit.confirm`
and the form's. A paste with a newline in it is joined into its row with a
space. `KitAccent` marks the focused field's label, `KitMuted` the others,
`KitError` the messages and the `*` of a required field.

The returned surface has five extra methods, for driving a sheet from code and
from specs: `s:submit()`, `s:cancel()`, `s:focus_field(name | index)`,
`s:validate()` (check every field now so the messages show, without submitting;
returns whether all passed — for a sheet opened with values that may already be
wrong) and `s:state()` (`{ focus = <field name | "submit" | "cancel">, values, errors }`).
Opening options: `focus` (field name or position to start on), `width`
(default 60), `relative` (default `"editor"`), `theme`.

### Live input (debounced on_change)

`kit.live_input(opts)` is `kit.input` plus a debounced `on_change(query)` —
for filter/search boxes that need to refresh a results list or preview on
every keystroke, not just on submit (`kit.picker`'s prompt slot uses the same
debounce timer internally).

```lua
kit.live_input({
  prompt = "Filter",
  debounce = 80,  -- ms after the last keystroke before on_change fires (default 80)
  on_change = function(query) end,   -- fired repeatedly as the user types
  on_submit = function(query) end,   -- <CR>
  on_cancel = function() end,        -- <Esc>
  -- row/col (relative="editor" only) override the default centered
  -- placement, e.g. to anchor the bar to the bottom edge of a host window.
})
```

### Secret input (masked entry)

`kit.input({ secret = true, ... })` masks the input as you type — a
`vim.fn.inputsecret` replacement. Each typed character is concealed behind
`opts.mask` (default `"*"`) via `conceal`, re-derived from the buffer's actual
content on every edit (paste, backspace, mid-line insert all just work). The
underlying buffer still holds the real text — `on_submit` reads it straight
off the buffer — but it's never echoed on screen, undo is disabled on that
buffer (`undolevels = -1`), and (like every kit scratch buffer) it was never
written to disk in the first place (`swapfile = false`) and is wiped the
moment the float closes.

```lua
kit.input({
  prompt = "Registry password",
  secret = true,
  on_submit = function(password) end,
})
```

### File-path completion

`kit.input({ completion = "file", ... })` — a `vim.fn.input(..., completion =
"file")` replacement. `<Tab>` completes the last whitespace-delimited
fragment before the cursor via `vim.fn.getcompletion()` and opens Neovim's
real completion popup (`vim.fn.complete()`), so `<C-n>`/`<C-p>` cycle it same
as anywhere else. While the popup is open, `<Tab>`/`<S-Tab>` advance/retreat
the selection instead of re-triggering, and `<CR>` accepts the highlighted
candidate rather than submitting the whole prompt (a second `<CR>` — popup
now closed — submits). `completion` accepts any type name `getcompletion()`
does (`"dir"`, `"shellcmd"`, `"buffer"`, ...), not just `"file"`.

```lua
kit.input({
  prompt = "Path to executable",
  completion = "file",
  on_submit = function(path) end,
})
```

### Sync bridge (blocking wrapper)

`kit.input`/`kit.form`/`kit.live_input` are async — `on_submit`/`on_cancel`
fire later, once the user responds. `kit.sync(open_fn, opts, timeout_ms?)`
bridges one of them back to a plain return value via `vim.wait()`, for call
chains built around a blocking `vim.fn.input()` that can't easily be recast
to callback style. Only safe to call from a normal call stack (a command
handler, keymap callback, ...) — never from a fast-event/libuv callback
context, the same restriction `vim.wait()` itself has.

```lua
local values, cancelled, timed_out = kit.sync(kit.form, {
  fields = {
    { name = "condition", label = "Condition", default = "condition" },
  },
}) -- default timeout: 10 minutes (a safety net, not the expected path)
if not cancelled and values then
  vim.notify(values.condition)
end
```
