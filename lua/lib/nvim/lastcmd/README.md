# `lib.nvim.lastcmd`

Repeat the last *real* command — mapping or native change — skipping pure
motions. Nothing has to be wrapped.

> **Experimental, and off until you ask for it.** The tracker listens to every
> keypress in the session, so it does not switch itself on just because the
> library is on the runtimepath. `experimental` is both the opt-in and the key.

```lua
require("lib.nvim.lastcmd").setup({ experimental = true })     -- default: <M-.>
require("lib.nvim.lastcmd").setup({ experimental = "<M-r>" })  -- your own key
```

The module binds the trigger itself (in normal and Visual mode, through
`lib.nvim.bindings.keymap`, so it shows up in the keymap registry like any
other binding). `setup({ experimental = false })` is the off switch and undoes
an earlier call; `setup()` with no `experimental` does nothing at all.

`3<M-Right>` then `5j` then `<M-.>` re-runs `3<M-Right>`. A later `<M-c>` then
`jjj` then `<M-.>` re-runs `<M-c>`. A native `dw` in between wins over both,
because it happened last.

## Why `<M-.>` and not `<C-#>`

Outside the kitty keyboard protocol a terminal has no encoding for Ctrl with a
non-alphabetic key. Legacy encoding only covers `Ctrl` + `@ A-Z [ \ ] ^ _ ?`;
press `Ctrl+#` anywhere else and the terminal sends a bare `#`, so a `<C-#>`
mapping is never reached — and `#` does its usual backwards word search
instead. Neovim can *represent* the key (`nvim_replace_termcodes("<C-#>")`
yields a real modified-key sequence), which is why binding it appears to
succeed and then silently never fires.

`<M-.>` survives the ESC-prefix encoding every terminal implements, and keeps
`.`'s "repeat" mnemonic. Pass `experimental = "<C-#>"` anyway if your terminal
speaks the kitty protocol and you have enabled it.

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
Vj<F8>  at line 1  ->  lines 1-2 acted on, shape recorded as "V, 2 lines"
<M-.>   at line 4  ->  lines 4-5 acted on
```

## Options

```lua
lastcmd.setup({
  experimental = true,              -- required opt-in: true | "<lhs>" | false
  ignore       = { "<M-j>", "<M-k>" }, -- mapped keys to treat as motions
  motions      = true,              -- false drops the built-in list entirely
})
```

## API

| | |
| --- | --- |
| `setup(opts?)` | Enable and bind the trigger. Returns whether it is on. Idempotent. |
| `repeat_last()` | Re-run the last real command. Returns whether anything ran. |
| `peek()` | The recorded mapping entry, or `nil` — inspection/tests. |
| `clear()` | Forget the recorded mapping and the per-buffer tick bookkeeping. |
| `enabled()` | Whether the tracker is installed. |
| `trigger_key()` | The lhs the trigger is bound to, or `nil` when off. |
| `teardown()` | Remove the tracker and the trigger keymap. |

## How the trigger avoids repeating itself

`on_key` runs *before* a mapping's rhs, so when the trigger's own keys are read
it looks like any other mapping and would be recorded as the thing to repeat —
after which repeating it repeats the trigger, which repeats the trigger, until
the editor stops responding.

Recording is therefore two-stage: `on_key` stores a *pending* entry and
promotes it one `vim.schedule` tick later, which lands after the rhs has run,
and `repeat_last` cancels whatever is in flight when it starts. That holds for
any lhs and for any wrapper around `repeat_last`.

Comparing the resolved mapping's callback against `repeat_last` — the obvious
guard, and the one this module shipped with — does **not**: every binding that
wraps the call in a closure (including the one this README used to recommend)
never matches, and the runaway was reachable straight from the documented
example.

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
- **Operator-pending** is indistinguishable here: `mode()` still reports `n`
  from inside `on_key` while an operator waits for its motion (measured), so
  the `w` of a `dw` is looked up as a normal-mode mapping. Harmless in
  practice — the built-in ignore list already covers the motion keys an
  operator takes — but a *mapped, non-motion* key used as an operator target
  would be recorded.
