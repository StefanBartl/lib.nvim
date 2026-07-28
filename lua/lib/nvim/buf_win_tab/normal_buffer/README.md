# `lib.nvim.buf_win_tab.normal_buffer`

Shared buffer/window primitives around "normal" file buffers.

A *normal file buffer* is a real, listed, loaded buffer backed by a readable
file on disk — i.e. not a terminal, tree, help, prompt, or scratch buffer.
These helpers are used by Neo-tree and the LazyGit bridge to find the editor
window to replace, edit a file in place without stealing focus, and
optionally prompt before discarding unsaved changes.

## Usage

```lua
local normal_buffer = require("lib.nvim.buf_win_tab.normal_buffer")

normal_buffer.is_normal_file_buffer(bufnr)     --> boolean
normal_buffer.find_last_normal_window(exclude) --> bufnr?, winid?
normal_buffer.edit_in_window(winid, path)      --> ok, err?
normal_buffer.prompt_save(bufnr)               --> proceed:boolean
```

### `is_normal_file_buffer(bufnr?)`

`true` only if `bufnr` (0 or nil = current buffer) is valid, loaded, has
`buftype == ""`, is `buflisted`, has a non-empty name, and that name is
`filereadable`. Anything failing one of those checks (including an unsaved
`[No Name]` buffer) is `false`.

### `find_last_normal_window(exclude_win?)`

Scans the current tabpage's windows in reverse (most recently laid out
first) and returns the buffer/window id of the first one showing a normal
file buffer, skipping `exclude_win` (e.g. the Neo-tree window). Returns `nil,
nil` if none is found.

### `edit_in_window(winid, path)`

Runs `:edit {path}` inside `winid` via `nvim_win_call`, without moving focus
there. Returns `false, "invalid window id"` / `false, "invalid path"` for bad
input, or `false, <error>` if the `:edit` itself fails.

### `prompt_save(bufnr)`

Blocking `vim.fn.confirm` prompt ("Save changes to `<name>`?") shown only if
`bufnr` is valid and modified; otherwise returns `true` immediately. Saves in
the buffer's own context (`nvim_buf_call` + `:write`) without changing focus
if the user picks Yes, returns `true` without saving on No, and `false` only
on Cancel/Esc. **Do not call this while a terminal float (e.g. LazyGit) owns
the screen** — the prompt would be invisible.
