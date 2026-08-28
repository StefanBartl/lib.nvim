# `lib.nvim.lastcmd`

Repeat the last *real* command — mapping or native change — skipping pure
motions. Nothing has to be wrapped.

```lua
require("lib.nvim.lastcmd").setup()

vim.keymap.set({ "n", "x" }, "<leader>.", function()
  require("lib.nvim.lastcmd").repeat_last()
end, { desc = "repeat last real command" })
```

`3<M-Right>` then `5j` then `<leader>.` re-runs `3<M-Right>`. A later `<M-c>`
then `jjj` then `<leader>.` re-runs `<M-c>`. A native `dw` in between wins
over both, because it happened last.

## Why native `.` is not enough

`.` cannot repeat a Lua-callback mapping. It replays the recorded *keystrokes*
of a change, and a mapping whose rhs is a Lua function edits the buffer
through the API, which never touches the redo machinery.

The failure mode is worse than doing nothing — measured, not assumed:

```
after x:     { "aa", "bbb", "ccc" }     -- a native change
after <F5>:  { "aa", "  bbb", "ccc" }   -- a Lua-callback mapping
after . :    { "aa", "  bbb", "cc" }    -- `.` replayed the *x*, not <F5>
```

`.` silently repeated an older, unrelated change. That is the gap this module
closes. (For the narrower case where you *do* want `.` itself to repeat one
specific buffer change, wire it through
[`lib.nvim.dotrepeat`](../dotrepeat/README.md) instead — that is a different
tool for a different job.)

## How it works

Two trackers, one arbiter.

**Mappings** are read off the key stream with `vim.on_key`, which reports keys
as *typed* — `3`, `<M-Right>` — regardless of what the mapping expands to. A
sequence is resolved against the keymap table: `maparg` non-empty means an
exact mapping, `mapcheck` non-empty means it is still a prefix of a longer
one. So `<leader>c` waits and `<leader>ct` fires, without guessing.

**Native changes are not parsed at all.** Vim already knows what the last
native change was, and `.` replays it correctly. Reimplementing Vim's
normal-mode grammar in Lua to re-derive that — operators, text objects,
counts in two positions, `r{char}`, `f{char}`, insert-mode-until-`<Esc>`,
Visual and cmdline as separate grammars — would be roughly a thousand lines
that are never quite right, and every gap is a silently wrong repeat. So the
only question asked is *did the buffer change after the last mapping ran*,
answered with `changedtick`.

Whichever is more recent wins: a mapping is replayed by feeding its keys, a
native change by running `normal! .`.

### Motion filtering is free

No motion parser, no big denylist to maintain:

- Motions do not change text, so they never move `changedtick`.
- An unmapped motion key never matches `maparg`.

Only a key that is *both* mapped and a motion needs naming. That is what the
built-in list (`hjkl`, arrows, `w`/`b`/`e`, `gg`/`G`, `<C-d>`, …) and
`opts.ignore` cover, and they only take effect when something actually mapped
one of those.

## Visual mode

A Visual mapping is recorded together with the selection's *shape*, and
replayed against an equally sized selection anchored at the cursor.

`{count}v` looks like it would do this and does not — it forces charwise, so a
linewise selection comes back as a single character (verified). The shape is
therefore measured and rebuilt through
[`lib.nvim.selection`](../selection/README.md).

```
Vj<F8>   at line 1   ->  lines 1-2 acted on, shape recorded as "V, 2 lines"
<leader>. at line 4  ->  lines 4-5 acted on
```

## Options

```lua
lastcmd.setup({
  ignore  = { "<M-j>", "<M-k>" },  -- mapped keys to treat as motions
  motions = true,                   -- false drops the built-in list entirely
})
```

## API

| | |
| --- | --- |
| `setup(opts?)` | Install the tracker. Idempotent. |
| `repeat_last()` | Re-run the last real command. Returns whether anything ran. |
| `peek()` | The recorded mapping entry, or `nil` — inspection/tests. |
| `clear()` | Forget the recorded mapping and the per-buffer tick bookkeeping. |
| `enabled()` | Whether the tracker is installed. |
| `teardown()` | Remove the tracker. |

The repeat key never records itself. Identity is checked against the resolved
mapping's callback, so that holds whatever lhs you pick and needs no config.

## Known limits

- **Native non-change commands** (`zz`, `<C-w>w`, `:w`) are invisible to
  `changedtick` and are never tracked. Only edits count as "real commands".
- **Undo/redo** move `changedtick`, so they read as a native change; `.` then
  does whatever `.` does after an undo rather than undoing again.
- **Ambiguous mappings** — an lhs that is both an exact mapping and the prefix
  of a longer one is recorded immediately, where Vim would wait for
  `timeoutlen`.
- **Insert- and cmdline-mode** keys are not tracked; native `.` already
  repeats insert-mode edits correctly.
