# `lib.nvim.treesitter.parser_policy`

Prompt-or-auto-install policy for missing-but-available treesitter parsers.

`lib.nvim.treesitter.guard` decides **whether** treesitter should activate for
a filetype at all (a curated allowlist); this module decides what happens
when it should, but the parser for that filetype's language isn't installed
yet. The modern `nvim-treesitter` (`main` branch) never auto-installs
anything — without a mechanism like this, a missing parser degrades silently
to no highlighting at all, with no error anywhere.

## Modes

| Mode | Behaviour |
|---|---|
| `"off"` | Do nothing. |
| `"prompt"` (default) | Ask once per language via a themed select prompt (`lib.nvim.ui.kit`): Yes / No / Never for this language. |
| `"auto"` | Install immediately, no prompt — just a short `notify.info`. |

A "Never for `<lang>`" answer is remembered in `stdpath("cache")` via
`lib.nvim.cache.disk` and survives restarts, so the same language never
re-prompts. "No" is *not* remembered — it asks again next time.

This module never calls `vim.treesitter.start()` itself. Callers pass
`opts.on_installed` to `ensure()` and decide what "the parser just became
available" means for their buffer(s).

## Usage

```lua
local policy = require("lib.nvim.treesitter.parser_policy")
policy.setup({ mode = "prompt" })

vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
    policy.ensure(lang, {
      on_installed = function()
        pcall(vim.treesitter.start, args.buf)
      end,
    })
  end,
})
```

Toggle at runtime from a user command:

```lua
require("lib.nvim.usercmd").create("TSParserPolicy", function(args)
  local policy = require("lib.nvim.treesitter.parser_policy")
  local mode = args.args
  if mode == "" then
    print(("mode=%s declined=%s"):format(policy.get_mode(), table.concat(policy.declined(), ",")))
  elseif mode == "reset" then
    policy.reset_declined()
  else
    local ok, err = policy.set_mode(mode)
    if not ok then vim.notify(err, vim.log.levels.WARN) end
  end
end, { nargs = "?", complete = function() return { "off", "prompt", "auto", "reset" } end })
```

## API

| Function | Meaning |
|---|---|
| `setup(opts?)` | `opts.mode` sets the initial mode (default `"prompt"`). |
| `get_mode()` | Current `Lib.Treesitter.ParserPolicy.Mode`. |
| `set_mode(mode)` | Switch mode at runtime. Returns `ok, err?`. |
| `declined()` | Sorted `string[]` of languages the user said "never" to. |
| `reset_declined()` | Clears the declined list, in memory and on disk. |
| `ensure(lang, opts?)` | Runs the policy for `lang`. No-op if `lang` is empty, already installed, not a known installable parser, mid-install/mid-prompt already, or (in `"prompt"` mode) declined. `opts.on_installed(lang)` fires once, only on a real successful install. |

## Why this is safe to call on every `FileType`

`ensure()` short-circuits immediately if the parser is already installed —
the `get_installed()`/`get_available()` lookups are cheap in-memory list
scans, not I/O — so wiring it into a `FileType` autocmd alongside the normal
`vim.treesitter.start()` call has no meaningful per-buffer cost once a
language's parser is present.
