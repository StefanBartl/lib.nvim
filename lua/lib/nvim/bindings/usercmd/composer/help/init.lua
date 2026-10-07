---@module 'lib.nvim.bindings.usercmd.composer.help'
--- Help float for composer verbs: the options that can follow what is typed,
--- one line each, `<CR>` puts the pick on the command line.
---
--- Two ways in, both opt-in (nothing changes until a verb or the setup asks):
---
---   1. **Cheatsheet key** -- in the command line, type `:Verb sub ` and press
---      `help.keymap`: the options of that level open as a float, before
---      anything is wrong. A pick lands in the command line and the line
---      reopens, so the next level is one key away. Esc restores the line as
---      it was.
---   2. **Instead of the usage notification** -- a bare `:Verb`, an
---      unfinished group (`:Cdx prompt`) or an unknown subcommand opens the
---      same float for that level, in place of the text from `parse.usage`.
---
---   composer.setup({ help = { enable = false, keymap = "<C-\\>h" } })
---   composer.verb("Clipboard", { help = true, ... })   -- opt this verb in
---
--- A verb is "on" when its `spec.help == true`, or `help.enable` is set and
--- `spec.help ~= false`. The cheatsheet key does nothing on a verb that is not
--- on (and on every non-composer command line).

local tree = require("lib.nvim.bindings.usercmd.composer.tree")
local entries_mod = require("lib.nvim.bindings.usercmd.composer.help.entries")
local registry = require("lib.nvim.bindings.usercmd.composer.registry")

local M = {}

---@type { enable: boolean, keymap: string|false|nil }
M.cfg = { enable = false, keymap = nil }

--- Applied keymap lhs, so a second `setup` replaces it instead of stacking.
---@type string|nil
local mapped

---@class Lib.UserCmd.Composer.Help.State
---@field name      string    # verb
---@field base      string    # command line up to (excluding) the token being typed
---@field committed string[]  # finished tokens after the verb
---@field lead      string    # the token being typed ("" when the line ends in a space)

--- Whether the help is on for a verb spec.
---@param spec Lib.UserCmd.Composer.Spec|nil
---@return boolean
function M.enabled(spec)
  if spec and spec.help ~= nil then
    return spec.help == true
  end
  return M.cfg.enable == true
end

---@internal
--- Split on whitespace that is not escaped with a backslash, as the command
--- line does for `-nargs=*`: `my\ file` stays one token (kept raw).
---@param text string
---@return string[]
local function split_tokens(text)
  local out, cur, i = {}, {}, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" and i < #text then
      cur[#cur + 1] = text:sub(i, i + 1)
      i = i + 2
    elseif c:match("%s") then
      if #cur > 0 then
        out[#out + 1] = table.concat(cur)
        cur = {}
      end
      i = i + 1
    else
      cur[#cur + 1] = c
      i = i + 1
    end
  end
  if #cur > 0 then
    out[#out + 1] = table.concat(cur)
  end
  return out
end

---@internal
--- The value of a raw token (`my\ file` -> `my file`), as `fargs` carries it.
---@param tok string
---@return string
local function unescape(tok)
  return (tok:gsub("\\(.)", "%1"))
end

---@internal
--- Back to command-line spelling: whitespace and backslashes escaped.
---@param tok string
---@return string
local function escape(tok)
  return (tok:gsub("([\\%s])", "\\%1"))
end

--- Split a command line into verb, finished tokens and the token being typed.
--- Understands a range/count prefix (`'<,'>`, `5,10`) and a bang. Pure.
---@param line string  # without the leading colon, as `getcmdline()` gives it
---@return Lib.UserCmd.Composer.Help.State|nil
function M.parse_line(line)
  local name, rest = line:match("^[%s:%d%.%$%%,;'<>%+%-/]*(%u[%w_]*)!?(.*)$")
  if not name then
    return nil
  end
  -- `Verbx=1` style: the name runs into a non-space, so it is not this verb.
  if rest ~= "" and not rest:match("^%s") then
    return nil
  end
  local raw = split_tokens(rest)
  local lead = ""
  if rest ~= "" and not rest:match("%s$") then
    lead = table.remove(raw)
  end
  local tokens = {}
  for i, tok in ipairs(raw) do
    tokens[i] = unescape(tok)
  end
  local base = line:sub(1, #line - #lead)
  if not base:match("%s$") then
    base = base .. " "
  end
  return { name = name, base = base, committed = tokens, lead = lead }
end

--- The command line after picking `entry`: everything before the typed
--- token, then the pick (and a space unless it continues, like `--type=`).
---@param state Lib.UserCmd.Composer.Help.State
---@param entry Lib.UserCmd.Composer.Help.Entry
---@return string
function M.insertion(state, entry)
  local text = (entry.insert or ""):gsub("%c", "")
  return state.base .. text .. (entry.partial and "" or " ")
end

---@internal
--- Put `line` on the command line, cursor at its end, ready to type on.
---@param line string
local function feed_cmdline(line)
  local keys = vim.api.nvim_replace_termcodes(":", true, false, true)
  -- Control characters (a literal <CR> typed with <C-v>) would execute the
  -- line instead of restoring it.
  vim.api.nvim_feedkeys(keys .. line:gsub("%c", ""), "nt", true)
end

--- Open the float for a state and wire the pick back into the command line.
---@param root Lib.UserCmd.Composer.Node
---@param state Lib.UserCmd.Composer.Help.State
---@param opts? { title?: string, restore?: string }  # restore: line to put back on Esc
---@return boolean opened
function M.open(root, state, opts)
  opts = opts or {}
  if #vim.api.nvim_list_uis() == 0 then
    return false
  end
  local result = entries_mod.compute(root, state.committed, state.lead)
  local title = opts.title
  if not title then
    local path = table.concat(state.committed, " ")
    title = ":" .. state.name .. (path ~= "" and (" " .. path) or "")
  end
  local restored = false
  local function restore()
    if opts.restore and not restored then
      restored = true
      feed_cmdline(opts.restore)
    end
  end
  local ok, opened =
    pcall(require("lib.nvim.bindings.usercmd.composer.help.ui").open, result.items, {
      title = title,
      on_pick = function(entry)
        restored = true
        feed_cmdline(M.insertion(state, entry))
      end,
      on_cancel = restore,
    })
  opened = ok and opened == true
  -- The key already left the command line: when no float came up, give the
  -- line back instead of leaving the user with nothing (once -- the float's
  -- own cancel path may have done it already).
  if not opened then
    restore()
  end
  return opened
end

---@internal
--- The route tree of a registered verb, or nil.
---@param name string
---@return Lib.UserCmd.Composer.Spec|nil spec
---@return Lib.UserCmd.Composer.Node|nil root
local function verb_tree(name)
  local handle = registry.get(name)
  if not handle then
    return nil, nil
  end
  local spec = handle:spec()
  return spec, tree.build(spec.routes or {})
end

--- Open the cheatsheet for the verb typed in `line`. False when `line` is not
--- a composer verb with the help turned on.
---@param line string
---@return boolean opened
function M.from_cmdline(line)
  local state = M.parse_line(line)
  if not state then
    return false
  end
  local spec, root = verb_tree(state.name)
  if not spec or not root or not M.enabled(spec) then
    return false
  end
  return M.open(root, state, { restore = line:match("^:") and line:sub(2) or line })
end

--- The `deps.help` hook for `parse.dispatch`: shows the level reached by
--- `tokens` instead of the usage text. Returns true when it took over; false
--- keeps the notification.
---@param name string
---@param spec Lib.UserCmd.Composer.Spec
---@param root Lib.UserCmd.Composer.Node
---@param tokens string[]  # literal tokens that matched
---@param reason? string   # why (e.g. "unknown subcommand 'x'"); becomes the float title
---@param fallback? fun()   # runs (scheduled) when the float could not open: shows the old notification
---@param cmd_opts? table   # command callback args: the range and bang the user typed
---@return boolean
function M.on_dispatch(name, spec, root, tokens, reason, fallback, cmd_opts)
  if not M.enabled(spec) then
    return false
  end
  if #vim.api.nvim_list_uis() == 0 then
    return false
  end
  local range = ""
  if cmd_opts and (cmd_opts.range or 0) > 0 then
    range = cmd_opts.range == 1 and tostring(cmd_opts.line2)
      or (cmd_opts.line1 .. "," .. cmd_opts.line2)
  end
  local bang = (cmd_opts and cmd_opts.bang) and "!" or ""
  local base = range
    .. name
    .. bang
    .. " "
    .. (#tokens > 0 and (table.concat(vim.tbl_map(escape, tokens), " ") .. " ") or "")
  local state = { name = name, base = base, committed = tokens, lead = "" }
  local title = reason and (":" .. name .. " - " .. reason) or nil
  -- Scheduled: the command that called us is still on the stack, and a float
  -- opened inside it is closed again by the command line's own redraw.
  vim.schedule(function()
    if not M.open(root, state, { title = title }) and fallback then
      fallback()
    end
  end)
  return true
end

---@internal
--- The expr-mapping body of the cheatsheet key.
---@param lhs string
---@return fun(): string
local function keymap_expr(lhs)
  return function()
    if vim.fn.getcmdtype() ~= ":" then
      return lhs
    end
    local line = vim.fn.getcmdline()
    local state = M.parse_line(line)
    local spec = state and verb_tree(state.name)
    if not (state and spec and M.enabled(spec)) then
      -- Not ours: the key keeps whatever it types without the mapping.
      return lhs
    end
    -- Leave the command line, then open the float from normal mode: a float
    -- cannot take focus while the command line is active.
    vim.schedule(function()
      M.from_cmdline(line)
    end)
    return "<C-c>"
  end
end

--- Map (or re-map) the cheatsheet key in command-line mode.
---@param lhs string|false|nil  # false/nil removes it
function M.set_keymap(lhs)
  if mapped then
    pcall(vim.keymap.del, "c", mapped)
    mapped = nil
  end
  if not lhs or lhs == "" then
    return
  end
  require("lib.nvim.bindings.keymap")("c", lhs, keymap_expr(lhs), {
    expr = true,
    -- Re-mappable at any time (`set_keymap`), so not a registry record that
    -- would outlive the key.
    record = false,
    desc = "composer: option cheatsheet for the verb on the command line",
  })
  mapped = lhs
end

--- Apply `composer.setup({ help = ... })`.
---@param opts? Lib.UserCmd.Composer.HelpOpts
function M.setup(opts)
  opts = opts or {}
  if opts.enable ~= nil then
    M.cfg.enable = opts.enable == true
  end
  if opts.keymap ~= nil then
    M.cfg.keymap = opts.keymap
    M.set_keymap(opts.keymap)
  end
end

---@type Lib.UserCmd.Composer.Help
return M
