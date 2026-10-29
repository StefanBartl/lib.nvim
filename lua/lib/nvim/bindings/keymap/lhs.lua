---@module 'lib.nvim.bindings.keymap.lhs'
--- Comparing keys: one spelling per physical key, one mode per mapping.
---@description
--- Two mappings collide when they claim the same *key*, and a key has more
--- spellings than a naive string compare knows: `<M-h>` and `<A-h>` are one key,
--- so are `<C-K>` and `<C-k>`, and `<leader>x` is whatever `mapleader` says it
--- is. `vim.fn.keytrans(vim.keycode(lhs))` is Neovim's own canonical form -- the
--- one `nvim_get_keymap()` reports -- so comparing through it agrees with what
--- the editor does.
---
--- Modes are the other half. `nvim_set_keymap()` takes short names that stand
--- for several real modes (`""` = n+x+s+o, `"v"` = x+s, `"!"` = i+c), while
--- `nvim_get_keymap()` only ever reports the real ones. `modes()` expands the
--- former so that a `:map` and a later `:nmap` are seen to meet in `n`.
---@see lib.nvim.bindings.keymap.tap
---@see lib.nvim.bindings.keymap.runtime

local M = {}

---@type table<string, string[]>
local EXPAND = {
  [""] = { "n", "x", "s", "o" },
  ["v"] = { "x", "s" },
  ["!"] = { "i", "c" },
}

---The canonical spelling of a key as Neovim itself would print it.
---
---Never raises: a notation Neovim cannot translate comes back unchanged, so
---one odd `lhs` costs a missed match and not a broken keymap.
---@param lhs string
---@return string
function M.normalize(lhs)
  if type(lhs) ~= "string" then
    return tostring(lhs)
  end
  local ok, keys = pcall(vim.keycode, lhs)
  if not ok or type(keys) ~= "string" then
    return lhs
  end
  local ok2, trans = pcall(vim.fn.keytrans, keys)
  if not ok2 or type(trans) ~= "string" or trans == "" then
    return lhs
  end
  return trans
end

---The real modes a `mode` argument stands for.
---
---`""` -> n, x, s, o; `"v"` -> x, s; `"!"` -> i, c; anything else is itself.
---A list (as `vim.keymap.set` takes) is expanded element by element, without
---duplicates.
---@param mode string|string[]|nil
---@return string[]
function M.modes(mode)
  local list = type(mode) == "table" and mode or { mode or "" }
  local out, seen = {}, {}
  for _, m in ipairs(list) do
    for _, real in ipairs(EXPAND[m] or { m }) do
      if not seen[real] then
        seen[real] = true
        out[#out + 1] = real
      end
    end
  end
  return out
end

---`"*"` for a global mapping, the buffer number for a buffer-local one.
---
---Buffer scope is part of a mapping's identity: the local one shadows the
---global one inside its buffer, which is its purpose and not a collision.
---@param buffer integer|boolean|nil
---@return string
function M.scope(buffer)
  if buffer == nil or buffer == false then
    return "*"
  end
  return tostring(buffer)
end

return M
