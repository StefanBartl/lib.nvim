-- docs/EXAMPLES/composer-flags-and-kv.lua
--
-- Module:   lib.nvim.bindings.usercmd.composer
-- Scenario: two grammars beyond plain positional args, both strictly
--           opt-in per route (a route without `flags`/`kv` behaves exactly
--           as before either feature existed):
--             `--flag[=value]` / `-x`   -- route.flags
--             bare `key=value`          -- route.kv
--
-- `path = {}` is a verb's ROOT route: it matches with zero literal
-- subcommand tokens, which is what lets a flat grammar like
-- `:Replace {old} {new} [scope] [--flags]` live on a composer verb without
-- inventing a new route shape for it.

local composer = require("lib.nvim.bindings.usercmd.composer")

-- 1. FLAGS -- modeled on replacer.nvim's own BOOL_FLAGS/VALUE_FLAGS split.
-- Flags may appear anywhere in the tail (before/after/between positionals),
-- and a literal "--" stops flag parsing. An undeclared "--name" is a hard
-- error, unlike an undeclared bare word (see kv below).
composer.verb("Replace", {
  routes = {
    {
      path = {}, -- root route: `:Replace old new ...`, no subcommand needed
      args = {
        { name = "old", type = "STRING" },
        { name = "new", type = "STRING" },
      },
      flags = {
        { name = "dry", bool = true }, -- --dry (no value)
        { name = "type", type = "STRING", repeatable = true }, -- --type=lua --type=md
        { name = "engine", type = "STRING", enum = { "fzf", "telescope" } },
        -- A short alias: -r and --replace are interchangeable, may be
        -- mixed freely, and only ever take their value from the NEXT
        -- token (never `-r=value`).
        { name = "replace", short = "r", bool = true },
      },
      run = function(ctx)
        -- ctx.args  = { old = "...", new = "..." }
        -- ctx.flags = { dry = true|nil, type = {"lua","md"}, engine = "fzf"|nil, replace = true|nil }
        require("replacer").run(ctx.args, ctx.flags)
      end,
    },
  },
})
-- :Replace foo bar --dry                  -> flags.dry == true
-- :Replace --dry foo bar --engine=fzf     -- flags may sit before positionals too
-- :Replace foo bar -r --type=lua          -- short alias, mixed with a long flag

-- 2. BARE KEY=VALUE -- a different grammar for routes where "--"/"-" would
-- be noise, e.g. `:Diff target=file.lua view=vsplit`. Unlike flags, an
-- UNDECLARED key=value-shaped token is left as an ordinary positional
-- rather than erroring -- "=" shows up in too many legitimate positional
-- values (URLs, passthrough env assignments, ...) to treat every match as
-- intentional.
composer.verb("Diff", {
  routes = {
    {
      path = {},
      kv = {
        { key = "target", type = "STRING" },
        { key = "view", type = "STRING", enum = { "vsplit", "split" }, default = "vsplit" },
      },
      run = function(ctx)
        -- ctx.kv.target, ctx.kv.view (default applied when the key is omitted)
        --
        -- diff.nvim's own module. Inside *this* workspace the bare name
        -- resolves to `lib.lua.diff` instead, which is why LuaLS reads the
        -- line as a second name for a file it already knows; for a reader
        -- who has diff.nvim installed it is simply the right call.
        ---@diagnostic disable-next-line: different-requires, undefined-field
        require("diff").open(ctx.kv.target, ctx.kv.view)
      end,
    },
  },
})
-- :Diff target=file.lua                 -> kv.target = "file.lua", kv.view = "vsplit" (default)
-- :Diff target=file.lua view=split      -> kv.view = "split"

-- `flags` and `kv` compose freely on the SAME route: parsing runs flags
-- first, then kv, then whatever tokens are left bind to positional `args`.
