# `lib.nvim.ui.statusline`

A short status badge pinned to one row of **one** window — the last row by
default (a status line), or the first (`anchor = "top"`, a header/breadcrumb).

## Why this exists

The obvious implementation — set that window's `&statusline` — silently shows
nothing under `laststatus = 3`, where Neovim draws a single global statusline
and no per-window one exists at all. A plugin cannot know (or dictate) the
user's `laststatus`, and a badge that only sometimes appears is not usable.

This module resolves the strategy at attach time instead:

| Mode           | Drawing                                                                  |
|----------------|--------------------------------------------------------------------------|
| `"statusline"` | Window-local `&statusline`, restored on detach.                          |
| `"float"`      | One-line, unfocusable float laid over the window's first or last row (`opts.anchor`), repositioned as the layout changes. |
| `"auto"`       | *(default)* `"statusline"` while a per-window statusline exists, `"float"` once `laststatus = 3` takes it away. |

`anchor` only affects `"float"` — a window's own `&statusline` is always its
last row, there is no top equivalent. A badge that must stay pinned to one
edge regardless of `laststatus` (a breadcrumb trail, always at the top) should
force `mode = "float"` rather than `"auto"`: `"auto"` would otherwise
alternate between an always-last-row statusline and a `"top"`-anchored float
depending on the user's setting, putting the badge in a different place
depending on config it has no business caring about.

## Usage

```lua
local statusline = require("lib.nvim.ui.statusline")

local badge = statusline.attach(tree_winid, { align = "left" })
badge.set("LOCK  ~/notes", "DiagnosticWarn")

badge.mode()   --> "statusline" or "float"
badge.clear()  -- hide, keep the attachment
badge.detach() -- remove and restore the previous &statusline
```

## Plain text, separate highlight

`set()` takes **plain** text and an optional highlight group, not a statusline
expression. Statusline `%#Group#` items mean nothing inside a float's buffer,
so a badge that must render identically in both strategies cannot carry them.
Percent signs in the text are escaped rather than interpreted.

For the same reason `align` is applied per strategy: `%=` items in statusline
mode, space padding in float mode.

## `attach(winid, opts)`

Returns `Lib.UI.Statusline.Segment`, or `nil, err` for an invalid window.

| Option   | Type                              | Default  | Meaning                                        |
|----------|-----------------------------------|----------|------------------------------------------------|
| `mode`   | `"auto"\|"statusline"\|"float"`   | `"auto"`   | Drawing strategy.                              |
| `align`  | `"left"\|"center"\|"right"`       | `"left"`   | Placement within the line.                     |
| `anchor` | `"top"\|"bottom"`                 | `"bottom"` | Float mode only: which row it sits on.         |
| `hl`     | `string?`                         | —          | Highlight group; overridable per `set`.        |
| `zindex` | `integer?`                        | `30`       | Float mode only.                               |

## Segment

| Method           | Meaning                                                            |
|------------------|--------------------------------------------------------------------|
| `mode()`         | The resolved strategy — never `"auto"`.                            |
| `text()`         | Current text (`""` when cleared).                                  |
| `set(text, hl?)` | Show `text`; an omitted `hl` keeps the previous one.                |
| `clear()`        | Hide without detaching.                                            |
| `refresh()`      | Redraw in place.                                                   |
| `detach()`       | Remove the badge; restores the previous `&statusline`.             |

## Notes

- In float mode the badge covers the window's last **content** row — under
  `laststatus = 3` there is no statusline row to sit on. That is the cost of
  being visible at all in that configuration.
- The float is positioned in absolute editor coordinates and is repositioned on
  `WinResized`/`VimResized`/`WinScrolled`/`WinEnter`/`TabEnter`/`WinNew`. There
  is no "window moved" event; these are the observable proxies.
- The float is editor-relative, so it hides while the target window is in
  another tabpage and comes back on return.
- The badge detaches itself when its window closes. Each attachment owns its
  own augroup, so independent badges never clear each other.
