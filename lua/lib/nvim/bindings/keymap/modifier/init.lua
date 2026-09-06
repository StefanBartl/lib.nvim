---@module 'lib.nvim.bindings.keymap.modifier'
--- Modifier keys that run *another* mapping and capture its result.
---
--- Press the modifier, then whatever keys you would normally press. The target
--- mapping runs exactly as it always does, and its result -- a path, a name, a
--- URL, whatever string it produced -- is put on the clipboard, and optionally
--- inserted at the cursor:
---
---   `\[a`   run `[a`, copy its result
---   `\\[a`  run `[a`, copy its result *and* insert it at the cursor
---
--- Nothing is wrapped and nothing has to cooperate: the modifier reads the
--- keys that follow it, resolves them against the keymap table itself, and
--- runs what it finds. Buffer-local mappings resolve too, which is the point
--- -- most interesting targets (a file tree's "yank path" family) are exactly
--- that.
---
--- **Mappings have no return value.** That is the whole difficulty. Vim
--- discards what a Lua rhs returns unless the mapping is `expr`, and then it
--- is read as *keys*, not as data. Wrapping every mapping does not fix this;
--- it only moves it, because the wrapped function still returns nothing. So
--- the result is resolved in tiers, from "fully declared" down to "observed
--- from the outside":
---
---   1. **declared** -- someone called `M.declare` for this lhs. Authoritative.
---   2. **returned**  -- the mapping's callback handed back a string.
---   3. **observed**  -- it did not, but a register moved while it ran. This
---      is the tier that needs no cooperation at all, and it covers the very
---      mappings that look hopeless: anything that already copies its result
---      to the clipboard is, by construction, readable this way.
---   4. **none**      -- nothing produced a string. The mapping still ran; the
---      modifier says so rather than pretending.
---
--- Usage:
--- ```lua
--- require("lib.nvim.bindings.keymap.modifier").setup({ experimental = true })
--- ```

require("lib.nvim.bindings.keymap.modifier.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.keymap.modifier]")

local M = {}

--- Default modifier keys.
---
--- `\` is free in a config that sets its own `mapleader` -- it is Vim's
--- *default* leader, so nothing builtin is lost. The second modifier is `\\`
--- rather than `?` deliberately: `?` is the backwards search, and taking a
--- builtin away to gain a modifier is a bad trade when one reserved prefix
--- can hold the whole family (`\i`, `\y`, ... cost no further keys).
local DEFAULTS = {
  copy = "\\",
  insert = "\\\\",
}

--- How many keys to read before giving up on resolving a target. Long enough
--- for any real mapping, short enough that a typo cannot swallow the session.
local MAX_SEQ = 8

--- Registers watched for tier 3. Order is priority: the system clipboard is
--- what a "copy the path" mapping almost always writes, so it wins over the
--- unnamed register that a plain yank also moves.
local WATCHED = { "+", "*", '"', "0" }

--- Declared result producers, keyed by `mode .. "\0" .. lhs`.
---@type table<string, fun(): string|nil>
local declarations = {}

--- Modifier lhs values currently bound, keyed by role.
---@type table<string, string|nil>
local installed = { copy = nil, insert = nil }

---Key for the declarations table.
---@param mode string
---@param lhs string
---@return string
local function declkey(mode, lhs)
  return mode .. "\0" .. lhs
end

---@param keys string
---@return string
local function termcodes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

---Read the keys typed after the modifier and resolve them to a mapping.
---
---Same rule the rest of lib.nvim uses for this: a non-empty `maparg` is an
---exact match, a non-empty `mapcheck` means the sequence is still the prefix
---of a longer mapping, so multi-key targets like `[a` need no special case.
---@return table|nil map, string seq
local function resolve_target()
  local seq = ""
  for _ = 1, MAX_SEQ do
    local got, ch = pcall(vim.fn.getcharstr)
    if not got or ch == nil or ch == "" then
      return nil, seq
    end

    local translated, t = pcall(vim.fn.keytrans, ch)
    if not translated then
      return nil, seq
    end
    if t == "<Esc>" then
      return nil, "" -- deliberate abort, not a failed lookup
    end

    seq = seq .. t

    local map = vim.fn.maparg(seq, "n", false, true)
    if type(map) == "table" and next(map) ~= nil then
      return map, seq
    end
    if vim.fn.mapcheck(seq, "n") == "" then
      return nil, seq
    end
  end
  return nil, seq
end

---@return table<string, string>
local function snapshot_registers()
  local snap = {}
  for _, r in ipairs(WATCHED) do
    local ok, value = pcall(vim.fn.getreg, r)
    snap[r] = ok and value or ""
  end
  return snap
end

---First watched register that changed to a non-empty value.
---@param before table<string, string>
---@return string|nil value, string|nil register
local function changed_register(before)
  for _, r in ipairs(WATCHED) do
    local ok, now = pcall(vim.fn.getreg, r)
    -- `getreg` answers with a string for every register this watches; the
    -- type also covers the list form of `getreg(r, 1, 1)`, which is not
    -- what is called here.
    if ok and type(now) == "string" and now ~= before[r] and now ~= "" then
      return now, r
    end
  end
  return nil, nil
end

---Run the resolved mapping, returning a string only when the mapping itself
---handed one back.
---
---A plain Lua callback is called, because that is the only way to see a
---return value at all. An `expr` mapping is *not*: its return value is a key
---sequence, and treating that as a result would be wrong -- it is fed
---instead, like a string rhs, which has no return value either.
---@param map table
---@param seq string
---@return string|nil returned
local function execute(map, seq)
  if map.expr == 1 or type(map.callback) ~= "function" then
    vim.api.nvim_feedkeys(termcodes(seq), "mx", false)
    return nil
  end

  local ok, ret = pcall(map.callback)
  if not ok then
    notify.warn(("`%s` errored: %s"):format(seq, tostring(ret)))
    return nil
  end
  if type(ret) == "string" and ret ~= "" then
    return ret
  end
  return nil
end

---Run the target and work out what its result was.
---@param map table
---@param seq string
---@return string|nil result, string tier
local function capture(map, seq)
  local before = snapshot_registers()
  local returned = execute(map, seq)

  --- CDX: only tier-1 declarations registered under mode "n" are ever consulted
  --- here, though `M.declare` accepts and stores an arbitrary mode. The whole
  --- feature is normal-mode only (resolve_target and setup both hardcode "n"),
  --- so a `declare("i"/"x", ...)` silently never matches.
  local declared = declarations[declkey("n", seq)]
  if declared then
    local ok, value = pcall(declared)
    if ok and type(value) == "string" and value ~= "" then
      return value, "declared"
    end
  end

  if returned ~= nil then
    return returned, "returned"
  end

  local observed, register = changed_register(before)
  if observed ~= nil then
    return observed, "observed " .. tostring(register)
  end

  return nil, "none"
end

---Can text be put into this buffer?
---@param buf integer
---@return boolean
local function writable(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local bo = vim.bo[buf]
  return bo.modifiable and not bo.readonly and bo.buftype == ""
end

---@param result string
local function to_clipboard(result)
  pcall(vim.fn.setreg, "+", result)
  pcall(vim.fn.setreg, '"', result)
end

---Buffers a result could reasonably be inserted into.
---@return integer[]
local function insertable_buffers()
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and writable(buf) then
      out[#out + 1] = buf
    end
  end
  return out
end

---Insert `result` as a new line before line `lnum` (1-based) of `buf`.
---@param buf integer
---@param lnum integer
---@param result string
local function insert_line(buf, lnum, result)
  local total = vim.api.nvim_buf_line_count(buf)
  local at = math.max(0, math.min(lnum - 1, total))
  local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, at, at, false, { result })
  if not ok then
    notify.warn("could not insert: " .. tostring(err))
    return
  end
  notify.info(
    ("inserted into %s at line %d"):format(
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
      at + 1
    )
  )
end

---Ask which buffer and line to insert into.
---
---Reached when the cursor is somewhere text cannot go -- a file tree, a
---terminal, any scratch surface -- which is the normal case for exactly the
---mappings this feature targets. Uses `vim.ui.*`, so whatever picker the user
---already installed is the one they get.
---@param result string
local function prompt_target(result)
  local buffers = insertable_buffers()
  if #buffers == 0 then
    notify.warn("copied, but no writable buffer is open to insert into")
    return
  end

  local labels = {}
  for i, buf in ipairs(buffers) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then
      name = "[No Name]"
    else
      name = vim.fn.fnamemodify(name, ":~:.")
    end
    labels[i] = ("%d  %s"):format(buf, name)
  end

  vim.ui.select(buffers, {
    prompt = "Insert into which buffer?",
    format_item = function(buf)
      for i, b in ipairs(buffers) do
        if b == buf then
          return labels[i]
        end
      end
      return tostring(buf)
    end,
  }, function(choice)
    if not choice then
      return
    end
    local default = tostring(vim.api.nvim_buf_line_count(choice))
    vim.ui.input({ prompt = "At which line? ", default = default }, function(answer)
      if not answer or answer == "" then
        return
      end
      local lnum = tonumber(answer)
      if not lnum then
        notify.warn("not a line number: " .. answer)
        return
      end
      insert_line(choice, math.floor(lnum), result)
    end)
  end)
end

---The modifier's rhs: resolve, run, capture, act.
---@param role "copy"|"insert"
local function invoke(role)
  local map, seq = resolve_target()
  if not map then
    if seq ~= "" then
      notify.warn(("nothing is mapped to `%s`"):format(seq))
    end
    return
  end

  local result, tier = capture(map, seq)
  if result == nil then
    notify.warn(("`%s` ran, but produced no result to capture (%s)"):format(seq, tier))
    return
  end

  to_clipboard(result)

  if role == "copy" then
    notify.info(("copied: %s"):format(result))
    return
  end

  if writable(vim.api.nvim_get_current_buf()) then
    pcall(vim.api.nvim_put, { result }, "c", true, true)
    return
  end
  prompt_target(result)
end

---Declare what a mapping's result is, for targets that neither return it nor
---move a register.
---
---The function must be pure: the mapping is run first, and this is called
---afterwards only to read the result out.
---@param mode string
---@param lhs string
---@param fn fun(): string|nil
function M.declare(mode, lhs, fn)
  if type(lhs) ~= "string" or type(fn) ~= "function" then
    notify.warn("declare() expects (mode, lhs, function)")
    return
  end
  declarations[declkey(mode, lhs)] = fn
end

---Forget a declaration made with `M.declare`.
---@param mode string
---@param lhs string
function M.undeclare(mode, lhs)
  declarations[declkey(mode, lhs)] = nil
end

---Remove whatever modifiers are currently bound.
function M.teardown()
  for role, lhs in pairs(installed) do
    if lhs then
      pcall(vim.keymap.del, "n", lhs)
      installed[role] = nil
    end
  end
end

---Bind the modifier keys.
---
---Opt-in, like `lib.nvim.lastcmd`: `\` is a key people do bind, and a library
---taking it just for being on the runtimepath would be overstepping.
---
---  * `experimental = nil|false` -- off, and undoes an earlier call.
---  * `experimental = true`      -- on, with `opts.copy` / `opts.insert`
---    defaulting to `\` and `\\`.
---@param opts? Lib.Keymap.Modifier.Opts
---@return boolean enabled
function M.setup(opts)
  opts = opts or {}

  if not opts.experimental then
    M.teardown()
    return false
  end

  local wanted = {
    copy = type(opts.copy) == "string" and opts.copy or DEFAULTS.copy,
    insert = type(opts.insert) == "string" and opts.insert or DEFAULTS.insert,
  }

  if wanted.copy == wanted.insert then
    notify.warn("`copy` and `insert` cannot be the same key")
    return false
  end

  M.teardown()

  local keymap = require("lib.nvim.bindings.keymap")
  for _, role in ipairs({ "copy", "insert" }) do
    local lhs = wanted[role]
    local desc = role == "copy" and "copy the next mapping's result"
      or "copy and insert the next mapping's result"
    local ok, err = pcall(keymap.set, "n", lhs, function()
      invoke(role)
    end, { silent = true }, desc)
    if ok then
      installed[role] = lhs
    else
      notify.warn(("could not bind %s: %s"):format(lhs, tostring(err)))
    end
  end

  return installed.copy ~= nil or installed.insert ~= nil
end

---Which lhs each modifier is bound to, or `nil` when off.
---@return { copy: string|nil, insert: string|nil }
function M.keys()
  return { copy = installed.copy, insert = installed.insert }
end

---@type Lib.Keymap.Modifier
return M
