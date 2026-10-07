---@module 'lib.nvim.bindings.usercmd.composer.help.entries'
--- The option list for one command-line state: which subcommands, arguments,
--- flags and key=value pairs can follow what has been typed so far.
---
--- Pure -- no windows, no globals -- and read from the same route tree that
--- drives dispatch and `<Tab>` completion, so the list can never drift from
--- what the command accepts. The float (`help.ui`) and the cmdline wiring
--- (`help`) only draw and insert what this returns.

local tree = require("lib.nvim.bindings.usercmd.composer.tree")
local flags = require("lib.nvim.bindings.usercmd.composer.flags")
local kv = require("lib.nvim.bindings.usercmd.composer.kv")
local format = require("lib.nvim.bindings.usercmd.composer.format")
local complete = require("lib.nvim.bindings.usercmd.composer.complete")

local M = {}

---@class Lib.UserCmd.Composer.Help.Entry
---@field kind     "heading"|"sub"|"group"|"value"|"flag"|"kv"|"hint"
---@field label    string         # what the row shows
---@field insert?  string         # text put on the command line (absent: not pickable)
---@field desc?    string         # one short line
---@field partial? boolean        # insert continues (`--type=`, `key=`): no trailing space

---@class Lib.UserCmd.Composer.Help.Result
---@field items      Lib.UserCmd.Composer.Help.Entry[]
---@field filtered   boolean   # the typed lead narrowed the list
---@field node       Lib.UserCmd.Composer.Node
---@field consumed   integer   # literal tokens the tree walk matched

--- Longest group summary ("a, b, c ...") shown as a group's description.
local SUMMARY_MAX = 44

---@internal
--- "a, b, c ..." for a group that has no description of its own.
---@param node Lib.UserCmd.Composer.Node
---@return string
local function summarize(node)
  local keys, len = {}, 0
  for _, k in ipairs(tree.child_keys(node)) do
    if complete.child_visible(node.children[k]) then
      keys[#keys + 1] = k
      -- Enough to fill the line (keys are sorted, so the shown prefix is the
      -- same): the rest would only run more `check`/`available` predicates.
      len = len + #k + 2
      if len > SUMMARY_MAX + 4 then
        break
      end
    end
  end
  local text = table.concat(keys, ", ")
  if #text > SUMMARY_MAX then
    text = text:sub(1, SUMMARY_MAX - 4):gsub("[,%s]+%S*$", "") .. " ..."
  end
  return text
end

---@internal
--- Entries for a closed set of values (`enum` or completion-only `values`).
---@param values string[]
---@param descs table<string, string>|nil
---@param prefix string|nil  # text before the value (`--type=`), if any
---@return Lib.UserCmd.Composer.Help.Entry[]
local function value_entries(values, descs, prefix)
  local out = {}
  for _, v in ipairs(values) do
    out[#out + 1] = {
      kind = "value",
      label = v,
      insert = (prefix or "") .. v,
      desc = descs and descs[v] or nil,
    }
  end
  return out
end

---@internal
--- Whether `tok` already passed this flag (long, `--name=…`, or short).
---@param spec Lib.UserCmd.Composer.FlagSpec
---@param tok string
---@return boolean
local function flag_used(spec, tok)
  if tok == "--" .. spec.name or vim.startswith(tok, "--" .. spec.name .. "=") then
    return true
  end
  return spec.short ~= nil and tok == "-" .. spec.short
end

---@internal
--- The flag rows of a route (without those already given, unless repeatable).
---@param route Lib.UserCmd.Composer.Route
---@param tail string[]  # tokens after the matched literals
---@return Lib.UserCmd.Composer.Help.Entry[]
local function flag_entries(route, tail)
  local out = {}
  for _, spec in ipairs(route.flags or {}) do
    local used = false
    for _, tok in ipairs(tail) do
      if flag_used(spec, tok) then
        used = true
        break
      end
    end
    if not used or spec.repeatable then
      local label = "--" .. spec.name .. (spec.short and ("|-" .. spec.short) or "")
      -- A flag whose value is optional is complete on its own (`--changed`
      -- binds true): the bare form is what gets inserted, `=value` is typed on.
      local needs_value = not spec.bool and not spec.optional_value
      if not spec.bool then
        local value = spec.enum and ("<" .. table.concat(spec.enum, "|") .. ">") or "<value>"
        label = label .. (spec.optional_value and ("[=" .. value .. "]") or ("=" .. value))
      end
      out[#out + 1] = {
        kind = "flag",
        label = label,
        insert = "--" .. spec.name .. (needs_value and "=" or ""),
        partial = needs_value,
        desc = spec.desc,
      }
    end
  end
  return out
end

---@internal
--- The key= rows of a route (without keys already given).
---@param route Lib.UserCmd.Composer.Route
---@param tail string[]
---@return Lib.UserCmd.Composer.Help.Entry[]
local function kv_entries(route, tail)
  local out = {}
  for _, spec in ipairs(route.kv or {}) do
    local used = false
    for _, tok in ipairs(tail) do
      if vim.startswith(tok, spec.key .. "=") then
        used = true
        break
      end
    end
    if not used then
      local hint = spec.enum and ("<" .. table.concat(spec.enum, "|") .. ">") or "<value>"
      out[#out + 1] = {
        kind = "kv",
        label = spec.key .. "=" .. hint,
        insert = spec.key .. "=",
        partial = true,
        desc = spec.desc,
      }
    end
  end
  return out
end

---@internal
--- The next positional argument of `route`, given how many are filled.
---@param route Lib.UserCmd.Composer.Route
---@param filled integer
---@return Lib.UserCmd.Composer.ArgSpec|nil
local function next_arg(route, filled)
  local specs = route.args or {}
  local spec = specs[filled + 1]
  if not spec then
    local last = specs[#specs]
    if last and last.variadic then
      return last
    end
  end
  return spec
end

---@internal
--- Rows for the next positional argument: its closed values when it has any,
--- otherwise one inert hint row ("{name} -- what it is for").
---@param spec Lib.UserCmd.Composer.ArgSpec
---@return Lib.UserCmd.Composer.Help.Entry[]
local function arg_entries(spec)
  local values = spec.enum or spec.values
  if values and #values > 0 then
    return value_entries(values, spec.enum_desc, nil)
  end
  return {
    {
      kind = "hint",
      label = format.arg_token(spec),
      desc = spec.desc or (spec.type and spec.type ~= "STRING" and spec.type or nil),
    },
  }
end

---@internal
--- The section an `--name=<lead>` / `key=<lead>` lead is typing a value for.
---@param route Lib.UserCmd.Composer.Route|nil
---@param lead string
---@param kv_only? boolean  # after a bare `--`: only `key=` values are still special
---@return Lib.UserCmd.Composer.Help.Entry[]|nil
local function value_of_lead(route, lead, kv_only)
  if not route then
    return nil
  end
  local fname = (not kv_only) and lead:match("^%-%-([%w_%-]+)=") or nil
  if fname then
    for _, spec in ipairs(route.flags or {}) do
      if spec.name == fname and not spec.bool then
        if spec.enum and #spec.enum > 0 then
          return value_entries(spec.enum, spec.enum_desc, "--" .. fname .. "=")
        end
        return {
          {
            kind = "hint",
            label = "--" .. fname .. "=<value>",
            desc = spec.desc or spec.type,
          },
        }
      end
    end
    return nil
  end
  local key = lead:match("^([%w_%-]+)=")
  if key then
    for _, spec in ipairs(route.kv or {}) do
      if spec.key == key then
        local values = spec.enum or spec.values
        if values and #values > 0 then
          return value_entries(values, spec.enum_desc, key .. "=")
        end
        return { { kind = "hint", label = key .. "=<value>", desc = spec.desc or spec.type } }
      end
    end
  end
  return nil
end

---@internal
--- `--name <lead>`: the flag's value is the next token (flags.split accepts
--- that spelling), so the line is waiting for one of its enum values.
---@param route Lib.UserCmd.Composer.Route|nil
---@param committed string[]
---@return Lib.UserCmd.Composer.Help.Entry[]|nil
local function pending_flag_value(route, committed)
  local last = committed[#committed]
  if not (route and last) then
    return nil
  end
  -- `--name` or its short alias `-x`: both take the next token as the value.
  local spec = flags.find_short_spec(route, last)
  local shown = "-" .. (spec and spec.short or "")
  if not spec then
    local name = last:match("^%-%-([%w_%-]+)$")
    for _, candidate in ipairs(name and route.flags or {}) do
      if candidate.name == name then
        spec = candidate
        shown = "--" .. name
        break
      end
    end
  end
  if not spec or spec.bool or spec.optional_value then
    return nil
  end
  if spec.enum and #spec.enum > 0 then
    return value_entries(spec.enum, spec.enum_desc, nil)
  end
  return { { kind = "hint", label = shown .. " <value>", desc = spec.desc or spec.type } }
end

---@internal
--- Keep the pickable entries whose `insert` starts with `lead`.
---@param entries Lib.UserCmd.Composer.Help.Entry[]
---@param lead string
---@return Lib.UserCmd.Composer.Help.Entry[]
local function narrow(entries, lead)
  if lead == "" then
    return entries
  end
  local out = {}
  for _, e in ipairs(entries) do
    if e.insert and vim.startswith(e.insert, lead) then
      out[#out + 1] = e
    end
  end
  return out
end

--- Compute the option list for the tokens typed so far.
---
--- `committed` are the finished tokens after the command word; `lead` is the
--- token being typed (`""` when the line ends in a space). A lead narrows the
--- list by prefix -- and when nothing matches it, the whole list is returned
--- instead of an empty float (`filtered = false`).
---@param root Lib.UserCmd.Composer.Node
---@param committed string[]
---@param lead? string
---@return Lib.UserCmd.Composer.Help.Result
function M.compute(root, committed, lead)
  lead = lead or ""
  local node, consumed = tree.walk(root, committed)
  local route = node.route

  local tail = {}
  for i = consumed + 1, #committed do
    tail[#tail + 1] = committed[i]
  end
  local clean = route and flags.strip(route, tail) or tail
  clean = route and kv.strip(route, clean) or clean
  local filled = #clean

  ---@type { title: string, entries: Lib.UserCmd.Composer.Help.Entry[] }[]
  local sections = {}
  local function add(title, entries)
    if entries and #entries > 0 then
      sections[#sections + 1] = { title = title, entries = entries }
    end
  end

  -- Everything after a bare `--` is positional for FLAGS (flags.split stops
  -- there), so no flag rows or flag values are offered past it. key=value
  -- pairs are another matter: kv.split knows nothing of `--`, so they stay.
  local after_dashes = false
  for _, tok in ipairs(tail) do
    if tok == "--" then
      after_dashes = true
      break
    end
  end

  local value_section
  if not after_dashes then
    value_section = value_of_lead(route, lead) or pending_flag_value(route, committed)
  else
    value_section = value_of_lead(route, lead, true)
  end
  if value_section then
    add("Value", value_section)
  else
    if next(node.children) ~= nil and (filled == 0 or not route) then
      local subs = {}
      for _, k in ipairs(tree.child_keys(node)) do
        local child = node.children[k]
        if complete.child_visible(child) then
          local group = next(child.children) ~= nil
          local desc = child.route and child.route.desc or nil
          if not desc and group then
            desc = summarize(child)
          end
          subs[#subs + 1] = {
            kind = group and "group" or "sub",
            label = k,
            insert = k,
            desc = desc,
          }
        end
      end
      add("Subcommands", subs)
    end
    if route then
      local spec = next_arg(route, filled)
      if spec then
        add("Argument", arg_entries(spec))
      end
      if not after_dashes then
        add("Flags", flag_entries(route, tail))
      end
      add("Key=value", kv_entries(route, tail))
    end
  end

  local filtered = false
  local items = {}
  local function flatten(narrowed)
    items = {}
    for _, sec in ipairs(sections) do
      local entries = narrowed and narrow(sec.entries, lead) or sec.entries
      if #entries > 0 then
        items[#items + 1] = { kind = "heading", label = sec.title }
        for _, e in ipairs(entries) do
          items[#items + 1] = e
        end
      end
    end
  end

  flatten(true)
  if #items == 0 and lead ~= "" then
    flatten(false)
  else
    filtered = lead ~= ""
  end

  return { items = items, filtered = filtered, node = node, consumed = consumed }
end

return M
