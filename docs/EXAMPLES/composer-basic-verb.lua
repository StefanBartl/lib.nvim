-- docs/EXAMPLES/composer-basic-verb.lua
--
-- Module:   lib.nvim.bindings.usercmd.composer
-- Scenario: turn the flat-command anti-pattern
--             :ReplaceBuffer   :ReplaceCwd   :ReplaceSurroundQuote
--           into one verb with subcommands and free <Tab> completion:
--             :Replace buffer
--             :Replace cwd [root]
--             :Replace surround quote <word>
--
-- One spec tree drives three things at once: dispatch, completion, and
-- (see composer-docgen scenario in the vimdoc) Markdown documentation --
-- there is no second place that needs to stay in sync by hand.
--
-- Call this once, e.g. from your plugin's setup()/plugin file.
--
-- CDX: replacer.nvim's real :Replace/:Surround registration (command.lua,
-- surround.lua) does use this composer module, but only single `path = {}`
-- root routes that forward ctx.raw into its pre-existing parser -- it never
-- declares a `buffer`/`cwd`/`surround` subcommand tree, and the module has
-- no `replace_prompt()`/`.buffer()`/`.cwd()`/`.surround()` functions (its
-- real public API is just `setup()`/`run()`). The `require("myplugin")`
-- stand-in below is illustrative of subcommand routing only.

local composer = require("lib.nvim.bindings.usercmd.composer")

composer.verb("Replace", {
  desc = "Text replacement operations",

  -- Bare `:Replace` with no subcommand at all falls through to `default`.
  default = function(ctx)
    require("myplugin").prompt()
  end,

  routes = {
    -- A route with no `args` is just a literal path plus a handler.
    {
      path = { "buffer" },
      desc = "Replace within the current buffer",
      run = function(ctx)
        require("myplugin").buffer()
      end,
    },

    -- `optional = true` means `:Replace cwd` and `:Replace cwd ~/notes`
    -- both dispatch here; `ctx.args.root` is nil in the first case. Typed
    -- as DIR, so <Tab> only offers directories and a non-directory value
    -- is rejected before `run` is ever called.
    {
      path = { "cwd" },
      args = { { name = "root", type = "DIR", optional = true } },
      desc = "Replace across the working tree (optionally under root)",
      run = function(ctx)
        require("myplugin").cwd(ctx.args.root)
      end,
    },

    -- `enum` on an ArgSpec is both a validator (the value must be one of
    -- the listed members, case-insensitive) and a completion source --
    -- `:Replace surround <Tab>` offers exactly `quote | paren | brace`.
    {
      path = { "surround" },
      args = {
        { name = "kind", type = "STRING", enum = { "quote", "paren", "brace" } },
        { name = "target", type = "STRING" },
      },
      desc = "Wrap TARGET with KIND surroundings",
      run = function(ctx)
        require("myplugin").surround(ctx.args.kind, ctx.args.target)
      end,
    },
  },
})

-- Result:
--   :Replace <Tab>                 -> buffer | cwd | surround
--   :Replace surround <Tab>        -> quote | paren | brace
--   :Replace surround quote hello  -> require("myplugin").surround("quote", "hello")
--   :Replace bogus                 -> notify + auto-generated usage, run() never called
