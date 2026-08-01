---@module 'lib.nvim.treesitter.parser_policy'
--- Prompt-or-auto-install policy for missing-but-available treesitter parsers.
---
--- `lib.nvim.treesitter.guard` decides WHETHER treesitter should activate for
--- a filetype at all (a curated allowlist); this module decides what happens
--- when it should, but the parser for that filetype's language simply isn't
--- installed yet. Three modes, switchable at runtime:
---
---   "off"    — do nothing (today's default behaviour before this module existed)
---   "prompt" — ask once per language via a themed select prompt (default)
---   "auto"   — install immediately, no prompt, just a short notify
---
--- A "Never for <lang>" answer in "prompt" mode is remembered in
--- `stdpath("cache")` via `lib.nvim.cache.disk` (survives restarts) so the
--- same language never re-prompts. `reset_declined()` clears that list.
---
--- This module never calls `vim.treesitter.start()` itself — callers pass
--- `opts.on_installed` to `ensure()` and decide what "the parser just
--- became available" means for their buffer(s).
---
--- Usage:
--- ```lua
--- local policy = require("lib.nvim.treesitter.parser_policy")
--- policy.setup({ mode = "prompt" })
---
--- vim.api.nvim_create_autocmd("FileType", {
---   callback = function(args)
---     local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
---     policy.ensure(lang, {
---       on_installed = function()
---         pcall(vim.treesitter.start, args.buf)
---       end,
---     })
---   end,
--- })
--- ```

require("lib.nvim.treesitter.parser_policy.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.treesitter.parser_policy]")
local disk = require("lib.nvim.cache.disk")

local CACHE_NS = "lib.nvim.treesitter.parser_policy"

---@type table<string, boolean>
local VALID_MODES = { off = true, prompt = true, auto = true }

---@type Lib.Treesitter.ParserPolicy.Mode
local MODE = "prompt"

---@type table<string, boolean> languages currently mid-install or mid-prompt
local PENDING = {}

---@type table<string, boolean> languages the user said "never" to
local DECLINED = {}

--- Load a previously persisted declined-set, if any. Best-effort: a missing
--- or unreadable cache file just leaves DECLINED empty, same as first run.
---@return nil
local function load_declined()
  local data = disk.load(CACHE_NS)
  if type(data) == "table" and type(data.declined) == "table" then
    DECLINED = data.declined
  end
end

load_declined()

---@return nil
local function persist_declined()
  local ok, err = disk.save(CACHE_NS, { declined = DECLINED })
  if not ok then
    notify.warn("failed to persist declined parsers: " .. tostring(err))
  end
end

---@param lang string
---@return nil
local function decline(lang)
  DECLINED[lang] = true
  persist_declined()
end

---@type Lib.Treesitter.ParserPolicy
local M = {}

---@param opts? Lib.Treesitter.ParserPolicy.SetupOpts
---@return nil
function M.setup(opts)
  opts = opts or {}
  if opts.mode ~= nil then
    local ok, err = M.set_mode(opts.mode)
    if not ok then
      notify.warn(err)
    end
  end
end

---@return Lib.Treesitter.ParserPolicy.Mode
function M.get_mode()
  return MODE
end

---@param mode Lib.Treesitter.ParserPolicy.Mode
---@return boolean ok
---@return string? err
function M.set_mode(mode)
  if not VALID_MODES[mode] then
    return false, ("invalid mode '%s' (expected off|prompt|auto)"):format(tostring(mode))
  end
  MODE = mode
  return true
end

---@return string[]
function M.declined()
  local out = {}
  for lang in pairs(DECLINED) do
    out[#out + 1] = lang
  end
  table.sort(out)
  return out
end

---@return nil
function M.reset_declined()
  DECLINED = {}
  disk.clear(CACHE_NS)
end

---@param lang string
---@param on_installed? fun(lang: string)
---@return nil
local function install(lang, on_installed)
  local ok_ts, ts = pcall(require, "nvim-treesitter")
  if not ok_ts or type(ts.install) ~= "function" then
    PENDING[lang] = nil
    return
  end

  PENDING[lang] = true
  notify.info(("installing parser '%s' …"):format(lang))

  local ok_call, task = pcall(ts.install, { lang })
  if not ok_call or type(task) ~= "table" or type(task.await) ~= "function" then
    PENDING[lang] = nil
    notify.warn(("could not start install for '%s'"):format(lang))
    return
  end

  task:await(function(err)
    PENDING[lang] = nil
    if err then
      notify.warn(("installing '%s' failed: %s"):format(lang, tostring(err)))
      return
    end
    notify.info(("parser '%s' installed"):format(lang))
    if type(on_installed) == "function" then
      pcall(on_installed, lang)
    end
  end)
end

---Ensure a treesitter parser is installed for `lang`, following the current
---policy mode. No-op if `lang` is empty, already installed, not a known
---installable parser, already pending, or (in "prompt" mode) declined.
---@param lang string
---@param opts? Lib.Treesitter.ParserPolicy.EnsureOpts
---@return nil
function M.ensure(lang, opts)
  opts = opts or {}
  if MODE == "off" or type(lang) ~= "string" or lang == "" then
    return
  end
  if PENDING[lang] then
    return
  end

  local ok_ts, ts = pcall(require, "nvim-treesitter")
  if not ok_ts or type(ts.get_installed) ~= "function" or type(ts.get_available) ~= "function" then
    return
  end

  for _, installed in ipairs(ts.get_installed()) do
    if installed == lang then
      return
    end
  end

  local available = false
  for _, candidate in ipairs(ts.get_available()) do
    if candidate == lang then
      available = true
      break
    end
  end
  if not available then
    return
  end

  if MODE == "auto" then
    install(lang, opts.on_installed)
    return
  end

  -- MODE == "prompt"
  if DECLINED[lang] then
    return
  end

  PENDING[lang] = true
  local ok_kit, kit = pcall(require, "lib.nvim.ui.kit")
  if not ok_kit then
    -- No UI toolkit available: fail safe to "do nothing" rather than a raw
    -- vim.ui.select, so this module never assumes a specific picker stack.
    PENDING[lang] = nil
    return
  end

  kit.popup({
    type = "select",
    message = ("Treesitter parser '%s' is not installed. Install now?"):format(lang),
    selection = { "Yes", "No", ("Never for '%s'"):format(lang) },
    respect_override = true,
    on_select = function(choice)
      PENDING[lang] = nil
      if choice == "Yes" then
        install(lang, opts.on_installed)
      elseif type(choice) == "string" and choice:match("^Never") then
        decline(lang)
      end
      -- "No": deliberately no state change - ask again next time.
    end,
    on_cancel = function()
      PENDING[lang] = nil
    end,
  })
end

return M
