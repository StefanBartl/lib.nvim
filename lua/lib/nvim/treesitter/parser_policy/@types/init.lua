---@meta
---@module 'lib.nvim.treesitter.parser_policy.@types'

---@alias Lib.Treesitter.ParserPolicy.Mode
---| '"off"'    # never prompt or install a missing parser
---| '"prompt"' # ask before installing (default)
---| '"auto"'   # install immediately, no prompt

---@class Lib.Treesitter.ParserPolicy.SetupOpts
---@field mode? Lib.Treesitter.ParserPolicy.Mode Initial mode. Defaults to `"prompt"`.

---@class Lib.Treesitter.ParserPolicy.EnsureOpts
---@field on_installed? fun(lang: string) Called once, after `lang` finishes installing successfully. Never called if the parser was already installed, declined, or the user answered "No".

--- `lib.nvim.treesitter.parser_policy` module surface.
---@class Lib.Treesitter.ParserPolicy
---@field setup fun(opts?: Lib.Treesitter.ParserPolicy.SetupOpts): nil
---@field get_mode fun(): Lib.Treesitter.ParserPolicy.Mode
---@field set_mode fun(mode: Lib.Treesitter.ParserPolicy.Mode): boolean, string?
---@field declined fun(): string[] Sorted list of languages the user chose "never" for.
---@field reset_declined fun(): nil Clears the declined list, in memory and on disk.
---@field ensure fun(lang: string, opts?: Lib.Treesitter.ParserPolicy.EnsureOpts): nil
