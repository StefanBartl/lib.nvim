# `lib.nvim_usrcmds`

Utility user commands that don't belong in a more specific plugin. Each
command is opt-in and can be toggled independently in `setup()`.

Two surfaces over the same actions, so the flat commands and the `:Lib` verb
never drift apart — both dispatch to the exact same action function:

- **Flat commands** (kept for muscle memory): `:CwdHere`, `:PowershellProfile`
- **The `:Lib` verb** (composer-built, `<Tab>`-completable, dogfoods
  [`lib.nvim.bindings.usercmd.composer`](../nvim/bindings/usercmd/composer/README.md)): `:Lib cwd-here`,
  `:Lib ps-profile`, `:Lib helptags`

## Usage

```lua
require("lib.nvim_usrcmds").setup({
  helptags = true,             -- regenerate helptags once lazy.nvim finishes loading
  cwd_here = true,              -- :CwdHere / :Lib cwd-here
  powershell_profile = vim.fn.has("win32") == 1,  -- :PowershellProfile / :Lib ps-profile
  lib_verb = true,               -- register the :Lib verb at all
})
```

## Commands

- `:CwdHere` / `:Lib cwd-here` — `:lcd` to the current buffer's directory
  (no-op on an unnamed buffer).
- `:PowershellProfile` / `:Lib ps-profile` — open the active PowerShell
  profile (`$PROFILE`) in Neovim; errors if `powershell` isn't on `PATH` or
  the profile path can't be resolved. Defaults to enabled only on
  `vim.fn.has("win32")`.
- `helptags = true` registers a one-shot `User LazyDone` autocmd that runs
  `:helptags ALL`, so generated help docs are indexed after plugins load.

`:Lib`'s route list only ever advertises actions whose flag is enabled, so it
can never offer something the flat commands would also omit.
