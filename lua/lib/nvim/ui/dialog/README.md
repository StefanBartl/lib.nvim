# `lib.nvim.ui.dialog`

The one way a plugin asks the user something: a yes/no, a choice of a few buttons, a line of text.
Every plugin used to carry its own wrapper around `ui.kit.confirm` with its own fallback when
ui.nvim is missing; this is that wrapper, once.

## Backends

The first that loads answers:

1. `ui.kit` (ui.nvim) -- the user's themed kit, presets included
2. `lib.nvim.ui.kit` -- the copy that ships with lib.nvim; looks the same
3. native -- `vim.ui.select` / `vim.ui.input` (also where a float that cannot open lands)

The kit is chosen per function: a `ui.kit` without `ask` hands `ask` to the next one. `dialog.backend()`
says which answers, `:checkhealth lib` shows it (and names a kit that is installed but fails to
load, `dialog.load_errors()`), and every call returns the backend that took the question.
An error the kit raises (a bad option, a throwing callback) is raised again: it is not a float that
failed to open, and a second, native question would leave two on screen.

## Contract

- The callback runs **exactly once**, and **never before the call has returned**: an answer given
  while the dialog is being opened (a native select that answers at once, a stub) is delivered on the
  next loop turn. `ask` with an `abandoned()` that turns true answers `nil` instead of asking.
- A dismissed dialog answers `false` (yes/no), `nil` (a `choices` list, text) or index `0` (`choose`).
- It is callback based and does not block. For straight-line code use `ui.kit`'s `kit.async` on top
  of it, not `vim.wait`.

## Usage

```lua
local dialog = require("lib.nvim.ui.dialog")

-- yes/no; with `choices` the answer is the label (nil when dismissed)
dialog.confirm({
  question = "Delete init.lua?",
  kind = "danger",           -- border and title in the status colour
  default = 2,               -- start on "No"
  on_answer = function(yes) if yes then delete() end end,
})

-- vim.fn.confirm as a callback: & marks the hotkey, the answer is the 1-based index, 0 = dismissed
dialog.choose("Save changes?", "&Save\n&Discard\n&Cancel", 1, function(i)
  if i == 1 then save() elseif i == 2 then discard() end
end, "Warning")

-- a line of text, the way vim.ui.input calls back (nil when cancelled)
dialog.input({ prompt = "Name", default = "untitled", completion = "file" }, function(name)
  if name then create(name) end
end)

-- a question raised at a moment the user did not pick (a stream that ends later):
-- it waits behind the dialog that is open instead of replacing it
dialog.ask({ question = "File the answer?", on_answer = function(yes) end })
```

`confirm`/`ask` take the options of `kit.confirm`/`kit.ask` (`question`, `choices` as a list or a
`vim.fn.confirm` string, `default`, `kind`, `legend`, `title`, `theme`, `keep_on_focus_lost`; `ask`
also `abandoned` and `max_wait_ms`). `input` takes those of `kit.input`; with a `secret` it uses the
kit's masked prompt, natively `vim.fn.inputsecret`.

The value does not depend on the backend: `expand_env` is applied natively too, and leaving `input` through
its `on_back` answers `nil` (after the caller's own `on_back` ran). Options only a float can honour
(`buttons`, `theme`, `mask`) are dropped by the native fallback. An error of the kit or of a native
provider is raised, and the callback is not left waiting. A NUL byte in a native prompt is made safe.

With `choices` the answer is the label **and its 1-based position** (`on_answer(label, index)`): two
buttons of the same text can be told apart. `choose` answers with that position.

`confirm` shows at once and replaces an open confirm (answering it as cancelled). Use `ask` for
anything a background event raises. See `ui.kit`'s README for the keys, hotkeys and focus rules.

Natively (no kit): `vim.ui.select` cannot preselect, so the `default` button is **listed first** (what
a lazy `<CR>` takes) and the position is mapped back to your order; there is no queue and no timeout
for `ask`; a `secret` goes through `vim.fn.inputsecret`, where an empty line counts as cancelled.

## Migrating a native prompt

| Before | After |
|---|---|
| `vim.fn.confirm(msg, "&Yes\n&No", 2) == 1` | `dialog.choose(msg, "&Yes\n&No", 2, function(i) if i == 1 then ... end end)` |
| `vim.ui.select({ "Yes", "No" }, ...)` as a question | `dialog.confirm({ question = msg, on_answer = ... })` |
| `vim.ui.input({ prompt = p }, cb)` | `dialog.input({ prompt = p }, cb)` (or keep it: a provider can route it to the kit) |
| a plugin-local `confirm.lua` wrapper | `dialog.confirm` / `dialog.ask` |

A prompt whose caller needs the answer **synchronously** (a documented return value) cannot move: it
stays a native call and is listed in the exception list of the rule against native prompts.
