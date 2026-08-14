# `kit.dashboard` — a persistent, activatable list, and a generic jump-target concept

> **Status: concept, analysis only — not yet built.** Extracted from
> [`UI-KIT-CONCEPT.md`](UI-KIT-CONCEPT.md) §15, where it was written as a
> speculative follow-on to the (fully shipped) `ui.kit` toolkit. Moved to its
> own file so it shows up as open work instead of being buried 900 lines into
> a historical design record — see that doc's own header for why it otherwise
> stays put (source comments point at its other sections by number).

**Trigger.** `reposcope.nvim`'s `:Reposcope status` (`ui/actions/status_view.lua`)
just grew row activation: `<CR>`/`<2-LeftMouse>` on a repository row asks for
confirmation (`kit.confirm`), then opens that repository's `README.md`
(`:edit`). It was wired by hand, buffer-local, per output backend (popup,
buffer, split, vsplit) — because nothing in `ui.kit` covers its shape: a
**persistent, buffer-backed list** (not a one-shot float) whose rows can be
**activated** to do something plausibly file-, URL-, or callback-shaped. This
section analyzes what's missing before building it, per the task that asked
for a concept rather than an immediate implementation.

## What already exists, and why it doesn't fit

Three components already give "a list of rows, Enter/double-click activates
one, callback fires" (`<2-LeftMouse>` → `M.submit` is literally one line in
`chooser.lua`, reused by every one of them):

| Component | Row shape | Lifecycle | Gap for a dashboard |
| --- | --- | --- | --- |
| `chooser` (engine) | string or rich `{lines, highlights?, anchor?}` | single-instance float, closes on activation/cancel | Not meant to stay open as a "home base"; every component built on it closes itself before the callback runs |
| `menu` | `{label, action}`, `action` is a bare zero-arg fn | cursor-anchored float, closes on pick | No concept of "what kind of thing does this row point at" — the row *is* its own handler, nothing else can introspect it (e.g. to preview, or to open in a split instead of running inline) |
| `picker` | raw highlighted line text, caller re-derives meaning | float, results owned by caller | `on_submit(idx, text)` hands back a *string*, not a value — same re-derivation problem, one layer worse |

None is a buffer a user can leave open in a real window/tab, come back to
later, resize, or reuse — which is exactly what `status_view.lua` needed
(its `buffer`/`split`/`vsplit` backends are ordinary windows, not floats).
That's the actual missing shape: not a new picker, a **dashboard** — list
content that outlives a single activation.

## The other missing half: a generic "target"

Even inside a single plugin, "what happens when you activate a row" already
varies: `status_view.lua` opens a file; `kit-menu.lua`'s context-menu example
runs a function; `kit-picker.lua`'s example also opens a file, but via
`vim.cmd.edit` on raw text, not a structured value. Across the ecosystem this
repo's own components motivated (filetree.nvim, github_stats.nvim, open.nvim,
gopath.nvim — see the module README), "jump to a thing" keeps meaning: open a
file, open a URL, run a callback, or `cd` into a directory. Nothing unifies
those today, and there are already **two independent** "open with OS default"
implementations (`lib.nvim.cross.open_default`, `lib.nvim.fs.open.url.system_opener`)
that a unified `activate()` would want to consolidate behind, not add a third
sibling of.

Proposed shape — a small tagged union carried as an extra field on a rich
chooser/dashboard item (chooser already hands the *original* item table back
to `on_select`, unstringified, so this is additive, not a new mechanism):

```lua
---@alias Lib.UI.Kit.Target
---| { kind: "file", path: string, split?: "edit"|"split"|"vsplit" }
---| { kind: "func", fn: fun(): nil }
---| { kind: "url",  value: string }
---| { kind: "cmd",  value: string, cwd?: string }
---| { kind: "dir",  path: string }

---@param target Lib.UI.Kit.Target
local function activate(target)
  local handlers = {
    file = function(t) vim.cmd[t.split or "edit"](vim.fn.fnameescape(t.path)) end,
    func = function(t) t.fn() end,
    url  = function(t) require("lib.nvim.fs.open.url.system_opener")(t.value) end,
    cmd  = function(t) require("lib.nvim.fs.open.url.system_opener")(t.value, { cwd = t.cwd }) end,
    dir  = function(t) vim.cmd.cd(vim.fn.fnameescape(t.path)) end,
  }
  handlers[target.kind](target)
end
```

`kind = "url"`/`"cmd"` deliberately route through one opener (recommendation:
keep `system_opener`, fold `cross.open_default` into it or behind it — a
separate cleanup, not scoped to this analysis) instead of each caller picking
whichever of the two pre-existing implementations it happens to know about.

## Sketch: `kit.dashboard`

Not `menu` extended in place — `menu` is deliberately cursor-anchored and
transient ("action list at cursor"); a dashboard is a **named, reusable,
window-hosted** list, closer to `open_named_scratch` + `chooser`'s row
handling than to `menu`. Sketch, following the existing callback-naming
convention (`on_select`/`on_submit`/`on_answer`/`on_change` — this reuses
`on_activate` to read as "the row itself was chosen," distinct from
`on_select` which several components already use for "highlight moved"):

```lua
kit.dashboard.open({
  name = "reposcope://status",         -- stable buffer name, de-duped like open_named_scratch
  lines = lines,                       -- or rich items, see below
  layout = "buffer" | "split" | "vsplit" | "popup",
  filetype = "reposcope-status",
  confirm = true,                      -- or a fun(item): string for a custom question
  on_activate = function(item, idx) … end,  -- fires after confirm (if any) says yes
})
```

- **Row → target mapping** is the caller's job, same as `chooser`'s rich
  items: `lines` can be plain strings (caller resolves `idx` itself, exactly
  what `status_view.lua` already does against its parallel `records` array),
  or rich items carrying a `.target` field, in which case `on_activate`
  becomes optional and the dashboard's own `activate()` dispatch (see above)
  runs by default — the "smart" default the task asked for, without forcing
  every caller to adopt it.
- **`confirm`** folds `kit.confirm`'s question-then-answer into the
  activation path directly (`status_view.lua` had to hand-roll this per
  backend); `confirm = false` skips straight to activation for callers that
  don't want a prompt (e.g. a read-only preview action).
- **Persistence**: reuses `open_named_scratch`'s find-or-create-by-name
  buffer for `split`/`vsplit`/`buffer` layouts, `surface` for `popup` —
  no new window primitive, same "reuse, don't reimplement" principle the
  rest of `ui.kit` follows.

## Migration path for `status_view.lua`

Out of scope for this analysis to execute, but worth recording the shape: if
`kit.dashboard` is built, `status_view.lua`'s four `show_*` backends collapse
to one `kit.dashboard.open({ layout = opts.output, lines = ..., on_activate =
function(_, idx) open_readme(records[idx]) end, confirm = function(_, idx)
return ('Open README.md of "%s"?'):format(records[idx].name) end })` call —
the per-backend `_attach_row_keymaps` duplication this session just added
would be exactly what the new component absorbs. Not done now because
`kit.dashboard` doesn't exist yet; recorded so the duplication is recognized
as temporary, not a second permanent pattern to keep in sync with the kit.

## Open questions

1. **Name.** `kit.dashboard` reads clearly next to `kit.picker`/`kit.menu`,
   but "dashboard" elsewhere in the ecosystem (alpha.nvim, dashboard-nvim)
   implies a startup-screen aesthetic (ASCII art, shortcuts) this is *not*
   trying to be — worth a bikeshed pass before committing to the name.
2. **Does `Lib.UI.Kit.Target` belong in `ui.kit` at all**, or in a lower
   layer (e.g. `lib.nvim.action` or similar) that both `ui.kit` dashboards
   *and* non-kit callers (`menu`, a future picker, plain keymaps) can share
   without depending on the kit? Leaning toward the latter — the dispatch
   table above has no float/buffer/theme dependency at all.
3. **Multi-select on a dashboard** — `chooser` already supports it
   (`multi_select`); whether `on_activate(items[], idxs[])` should exist for
   "open all READMEs of the marked rows" style bulk actions, or whether that
   is scope creep for a v1, is undecided.
