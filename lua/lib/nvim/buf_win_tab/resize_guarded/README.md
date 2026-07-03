# Developer README — lib.nvim.buf_win_tab.resize_guarded

## Purpose

This module provides a helper to enable window-resize shortcuts (e.g. Shift+H/J/K/L)
in normal editors, without those shortcuts suppressing input in embedded
terminals or special plugin buffers (e.g. lazygit).

---

## Problem statement

By default, a mapping set in Neovim (including in terminal mode) fully overrides
the incoming key. If the mapping merely 'does nothing' in terminal buffers (an
early `return`), the key is still not forwarded to the terminal process. This
leads, for example, to uppercase letters no longer appearing while writing a
commit message in lazygit, because `<S-h>` is intercepted by the mapping.

---

## Solution concept of this module

- The module creates a callback function for `vim.keymap.set`.
- This callback checks whether the current buffer is in an exclusion list
  (filetype or buffer-name pattern).
  - If excluded: the module forwards the **original key** to the terminal
    (using `nvim_replace_termcodes` + `nvim_feedkeys`) — so the terminal process
    receives the real input.
  - If not excluded: the module runs the specified resize command (`vim.cmd`).
- The original key is derived from the `lhs`. For common cases (`<S-h>` etc.) the
  correct entry is determined automatically. Extensions are possible via
  `COMMON_FALLBACK`.

---

## API

`create(cmd, exclude_filetypes?, exclude_names?, lhs?) -> function`

Parameters:
- `cmd` (string): The resize command to run, e.g. `"vertical resize -5"`.
- `exclude_filetypes` (string[], optional): List of `filetype` values for which
  the mapping should **not** perform the resize (e.g. `{ "terminal" }`).
- `exclude_names` (string[], optional): List of Lua patterns applied to
  `api.nvim_buf_get_name(buf)`; a match leads to the same behavior as
  `exclude_filetypes`.
- `lhs` (string, optional): The original mapping LHS, e.g. `"<S-h>"`. Used to
  derive the key to forward for excluded buffers.

Return value:
- A function compatible with `vim.keymap.set(..., callback)`.

---

## Examples

In a keymap file:

```lua
local resize_guarded = require("lib.nvim.buf_win_tab.resize_guarded")
local exclude_filetypes = { "terminal" }
local exclude_names = { ".*lazygit.*" }

vim.keymap.set({ "n", "t" }, "<S-h>", resize_guarded.create("vertical resize -5", exclude_filetypes, exclude_names, "<S-h>"), { desc = "[Window] Resize narrower" })
vim.keymap.set({ "n", "t" }, "<S-l>", resize_guarded.create("vertical resize +5", exclude_filetypes, exclude_names, "<S-l>"), { desc = "[Window] Resize wider" })
vim.keymap.set({ "n", "t" }, "<S-k>", resize_guarded.create("resize +5", exclude_filetypes, exclude_names, "<S-k>"), { desc = "[Window] Resize taller" })
vim.keymap.set({ "n", "t" }, "<S-j>", resize_guarded.create("resize -5", exclude_filetypes, exclude_names, "<S-j>"), { desc = "[Window] Resize shorter" })
```

---

## Important technical detail

* Forwarding uses `nvim_replace_termcodes` to ensure that termcodes like
  `<S-Left>` are correctly converted into keys, and `nvim_feedkeys` to actually
  pass the keys to the terminal subprocesses.
* Forwarding uses the `n` flag (no remap) with `nvim_feedkeys`, so that no
  recursive mappings arise.

---

## Extensions / customization

* `COMMON_FALLBACK` can be extended to cover further LHS → forward sequences.
* If other keys (e.g. Ctrl+Shift combinations or function keys) should be
  supported, the derivation logic in `derive_fallback` can be extended.
* If special cases exist (e.g. certain plugin buffers that need their own
  keycodes), they can be covered via `exclude_names` or `exclude_filetypes`.

---

## Debugging

* If keys still do not get through in a certain buffer:

  1. Check whether the buffer filetype is really contained in `exclude_filetypes`.
  2. Check whether the buffer name (`:echo bufname('%')`) matches one of the
     patterns in `exclude_names`.
  3. In a Lua REPL, test what `derive_fallback("<S-h>")` returns, to make sure a
     forward sequence exists.
  4. If needed, temporarily add `print()` or `vim.notify()` output inside the
     generated callback function.

---

## File location

* Module: `lua/lib/buf_win_tab/resize_guarded.lua`

-
