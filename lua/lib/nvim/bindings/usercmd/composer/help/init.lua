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
---@return string[] tokens
---@return boolean open  # the last token is still being typed (text does not end in unescaped whitespace)
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
  local open = #cur > 0
  if open then
    out[#out + 1] = table.concat(cur)
  end
  return out, open
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
  -- Whether the last token is still open is the tokenizer's call, not
  -- "does the text end in a blank": `my\ ` ends in one, yet nvim hands that
  -- to a completion function as the lead `my\ `.
  local raw, open = split_tokens(rest)
  local lead = open and table.remove(raw) or ""
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

--- Well-formed UTF-8 sequences (RFC 3629: no overlongs, no surrogates, nothing
--- above U+10FFFF), longest alternatives first. Anything that does not start
--- one of these at the current byte is dropped by `sanitize`.
---@type string[]
local UTF8_SEQ = {
  "[\1-\127]",
  "[\194-\223][\128-\191]",
  "\224[\160-\191][\128-\191]",
  "[\225-\236][\128-\191][\128-\191]",
  "\237[\128-\159][\128-\191]",
  "[\238-\239][\128-\191][\128-\191]",
  "\240[\144-\191][\128-\191][\128-\191]",
  "[\241-\243][\128-\191][\128-\191][\128-\191]",
  "\244[\128-\143][\128-\191][\128-\191]",
}

--- What may be replayed through the typeahead: printable text only. Control
--- characters (a literal <CR> typed with <C-v>) would execute the line instead
--- of restoring it, and so would a stray byte 0x80 -- `nvim_feedkeys` reads
--- `0x80 'K' 'A'` as <kEnter> -- so everything that is not well-formed UTF-8
--- (and the C1 controls U+0080..U+009F) is dropped, byte for byte.
---@param line string
---@return string
local function sanitize(line)
  local out, i, n = {}, 1, #line
  while i <= n do
    local len
    for _, pat in ipairs(UTF8_SEQ) do
      local _, e = line:find("^" .. pat, i)
      if e then
        len = e - i + 1
        break
      end
    end
    if len then
      local seq = line:sub(i, i + len - 1)
      -- Controls are not text: ASCII 1..31 and DEL, and the C1 range (C2 80..C2 9F).
      local control = (len == 1 and (seq:byte() < 32 or seq == "\127"))
        or seq:find("^\194[\128-\159]")
      if not control then
        out[#out + 1] = seq
      end
    end
    -- A byte that starts no well-formed sequence (and NUL) is skipped alone.
    i = i + (len or 1)
  end
  return table.concat(out)
end

M.sanitize = sanitize

---@internal
--- Put `line` on the command line, cursor at its end, ready to type on.
---@param line string
local function feed_cmdline(line)
  local keys = vim.api.nvim_replace_termcodes(":", true, false, true)
  vim.api.nvim_feedkeys(keys .. sanitize(line), "nt", true)
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
  -- The chooser is a normal-mode list: from an insert-mode mapping, or a
  -- pending insert (`i<C-o>:Verb`), <CR> would type a newline into it instead
  -- of picking.
  pcall(vim.cmd, "stopinsert")
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
---@param restore_if_refused? boolean  # the command line was already left: put it back when this is not a help-enabled composer verb
---@return boolean opened
function M.from_cmdline(line, restore_if_refused)
  local restore = line:match("^:") and line:sub(2) or line
  local state = M.parse_line(line)
  local spec, root
  if state then
    spec, root = verb_tree(state.name)
  end
  if not (state and spec and root and M.enabled(spec)) then
    if restore_if_refused then
      feed_cmdline(restore)
    end
    return false
  end
  return M.open(root, state, { restore = restore })
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
--- The lazy.nvim plugin that has not loaded yet and owns the user command
--- `name` (a stub until then: no composer handle exists to look at), or nil.
--- Soft: nothing happens without lazy.nvim.
---@param name string
---@return string|nil plugin
local function lazy_owner(name)
  local cfg = package.loaded["lazy.core.config"]
  if not (cfg and type(cfg.plugins) == "table") then
    return nil
  end
  for plugin_name, plugin in pairs(cfg.plugins) do
    if not (plugin._ and plugin._.loaded) then
      local cmds = plugin.cmd
      if type(cmds) == "string" then
        cmds = { cmds }
      end
      if type(cmds) == "table" and vim.tbl_contains(cmds, name) then
        return plugin_name
      end
    end
  end
  return nil
end

---@internal
--- What the key returns when the line is not ours. A Meta key does nothing
--- useful unmapped in the command line (Neovim reads <M-h> as <Esc>h: the line
--- is cancelled and an `h` follows), so it is swallowed; any other key keeps
--- typing itself.
---@param lhs string
---@return string
local function passthrough(lhs)
  if lhs:lower():find("^<[ma]%-") then
    return ""
  end
  return lhs
end

---@internal
--- The expr-mapping body of the cheatsheet key.
---@param lhs string
---@return fun(): string
local function keymap_expr(lhs)
  return function()
    if vim.fn.getcmdtype() ~= ":" then
      return passthrough(lhs)
    end
    local line = vim.fn.getcmdline()
    local state = M.parse_line(line)
    if not state then
      return passthrough(lhs)
    end
    local spec = verb_tree(state.name)
    if spec then
      if not M.enabled(spec) then
        return passthrough(lhs)
      end
      -- Leave the command line, then open the float from normal mode: a float
      -- cannot take focus while the command line is active.
      vim.schedule(function()
        M.from_cmdline(line)
      end)
      return "<C-c>"
    end
    -- No composer handle yet: either not a composer verb, or a lazy stub whose
    -- plugin has not loaded (and so has not registered its verb). Load the
    -- latter; the line comes back if it turns out not to be ours after all.
    local owner = lazy_owner(state.name)
    if not owner then
      return passthrough(lhs)
    end
    vim.schedule(function()
      pcall(function()
        require("lazy").load({ plugins = { owner }, wait = true })
      end)
      M.from_cmdline(line, true)
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
