# `lib.nvim.ui.list`

Quickfix and location lists: the mechanical last step of "show the user what I
found", written once instead of once per plugin.

Building the entries stays with the plugin. What this owns is handing them to
Vim with a title, deciding whether to open the window, and where the cursor
ends up afterwards.

## Usage

```lua
local list = require("lib.nvim.ui.list")

-- Quickfix, opened, cursor lands in the list (what bare `:copen` does).
list.qf(items, "myplugin: broken links")

-- Open only if there is something to show, and keep working in the buffer.
list.qf(items, "myplugin: matches", { open = "auto", focus = "source" })

-- Location list of the current window.
list.loc(items, "myplugin: this buffer")

-- Refresh a list that is already open, without pushing a new one.
list.set({ items = items, title = title, action = "r", open = false })
```

`qf`/`loc` return the number of entries placed, so `if list.qf(...) == 0 then`
is a legal way to report "nothing found".

## Options

| Option | Default | Meaning |
|---|---|---|
| `items` | `{}` | Entries, as `setqflist()` takes them. Empty **clears** the list. |
| `title` | none | Shown in the list's status line. |
| `loclist` | `false` | `true` = current window's location list, a window id = that window's, `false` = quickfix. |
| `action` | `" "` | `" "` pushes a new list, `"r"` replaces the current one, `"a"` appends. |
| `open` | `true` | `true` always opens, `"auto"` only when non-empty, `false` never. |
| `focus` | `"list"` | `"source"` hands the cursor back to the window the call came from. |
| `height` | none | Passed to `:copen`/`:lopen`. |

## Why the defaults are these defaults

**`action = " "`.** `setqflist(items, "r")` replaces the list the user is
currently looking at; `" "` pushes a new one and leaves `:colder` a way back.
Replacing is right when *refreshing your own* list and wrong otherwise, so it
is the thing a caller has to ask for.

**Title in the same call.** The `"r"` form cannot carry a title, which is why
`setqflist({}, "a", { title = ... })` -- an append of nothing -- shows up right
after it in so much plugin code. One call does both.

**`focus = "list"`.** It is what `:copen` alone does. A shared helper that
quietly moved the cursor somewhere else would change the feel of every plugin
adopting it; `"source"` is available for lists meant to be read next to the
buffer they describe.

**`open = "auto"` exists because of the empty case.** An empty list window
tells the user nothing and takes half the screen. `"auto"` skips the window but
still sets the list -- so a run that finds nothing clears the previous run's
findings instead of leaving them on screen as if they were current.

## Not in scope

Filtering, formatting, and navigation. Diagnostics have their own list
functions (`vim.diagnostic.setqflist`, `setloclist`) with severity handling
and a version-dependent signature; those are a separate API and are not
wrapped here.
