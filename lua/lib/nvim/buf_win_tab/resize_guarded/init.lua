---@module 'lib.nvim.buf_win_tab.resize_guarded'
--- Guarded resize helper that allows window resize shortcuts in normal editors
--- while preserving keypresses in terminals and special plugin buffers.
---
--- Usage:
--- local resize_guarded = require("lib.nvim.buf_win_tab.resize_guarded")
--- local exclude_filetypes = { "terminal" }
--- local exclude_names = { ".*lazygit.*" }
--- vim.keymap.set({ "n", "t" }, "<S-h>", resize_guarded.create("vertical resize -5", exclude_filetypes, exclude_names, "<S-h>"), { desc = "[Window] Resize narrower" })
---
--- Behavior:
--- - If current buffer matches an exclusion (filetype or name pattern),
---   forwards the original keypress to the buffer (terminals/plugins receive it).
--- - Otherwise executes the provided resize command.
--- - The `lhs` argument is REQUIRED to derive the correct key to forward.
---
--- API: create(cmd, exclude_filetypes?, exclude_names?, lhs)
---   returns a function suitable for `vim.keymap.set` callbacks.

local notify = require("lib.nvim.notify").create("[lib.nvim.buf_win_tab.resize_guarded]")

local api = vim.api
local replace_termcodes = vim.api.nvim_replace_termcodes
local feedkeys = vim.api.nvim_feedkeys

local M = {}

--- Map of common lhs -> fallback sequence for terminal forwarding.
--- These map shift-modified keys to their uppercase equivalents.
---@type table<string, string>
local COMMON_FALLBACK = {
  ["<S-h>"] = "H",
  ["<S-j>"] = "J",
  ["<S-k>"] = "K",
  ["<S-l>"] = "L",
  ["<S-Up>"] = "<S-Up>",
  ["<S-Down>"] = "<S-Down>",
  ["<S-Left>"] = "<S-Left>",
  ["<S-Right>"] = "<S-Right>",
}

--- Derive the key sequence to forward from the mapping's lhs.
--- Converts shift-modified keys (e.g., <S-h>) to their terminal representation (e.g., "H").
---@param lhs string|nil The left-hand side of the mapping (e.g., "<S-h>")
---@return string|nil fallback_seq The sequence to send to the terminal, or nil if derivation fails
local function derive_fallback(lhs)
  -- Validate input parameter
  if type(lhs) ~= "string" or lhs == "" then
    return nil
  end

  -- First check: lookup in predefined common mappings table
  local v = COMMON_FALLBACK[lhs]
  if v then
    return v
  end

  -- Second check: pattern match for <S-x> where x is a single character
  -- Example: "<S-a>" -> "A"
  local single = lhs:match("^<S%-(.)>$")
  if single and #single == 1 then
    return single:upper()
  end

  -- Third check: pattern match for <S-token> with multi-character token
  -- Example: "<S-Up>" -> "<S-Up>" (to be processed by replace_termcodes)
  local token = lhs:match("^<S%-(.+)>$")
  if token and #token > 1 then
    return "<S-" .. token .. ">"
  end

  -- No matching pattern found
  return nil
end

--- Forward a key sequence to the active buffer/terminal.
--- Uses nvim_replace_termcodes to convert special key notation,
--- then nvim_feedkeys to inject the keys as if typed by the user.
---@param seq string The key sequence to forward (e.g., "H" or "<S-Up>")
local function forward_key(seq)
  -- Validate input sequence
  if not seq or seq == "" then
    return
  end

  -- Convert special key notation (like <S-Up>) to internal keycodes
  -- Parameters: string, from_part, do_lt, special
  local keys = replace_termcodes(seq, true, false, true)

  -- Feed keys to Neovim
  -- Flags: 'n' = no remap (prevents recursive mapping triggers)
  -- escape_ks: false (keys are already escaped by replace_termcodes)
  feedkeys(keys, "n", false)
end

--- Create a guarded resize mapping callback function.
--- This function checks if the current buffer should be excluded,
--- and either forwards the key or executes the resize command.
---@param cmd string The resize command to execute (e.g., "vertical resize -5")
---@param exclude_filetypes string[]|nil List of filetypes to exclude from resize
---@param exclude_names string[]|nil List of Lua patterns matching buffer names to exclude
---@param lhs string The original mapping lhs (e.g., "<S-h>") - REQUIRED for key forwarding
---@return function callback Function compatible with vim.keymap.set
function M.create(cmd, exclude_filetypes, exclude_names, lhs)
  -- Set default values for optional parameters
  exclude_filetypes = exclude_filetypes or {}
  exclude_names = exclude_names or {}

  -- Derive the fallback key sequence once at mapping creation time
  -- This is more efficient than computing it on every keypress
  local fallback_seq = derive_fallback(lhs)

  -- Warn if lhs was provided but fallback derivation failed
  if lhs and not fallback_seq then
    notify.warn(string.format("[resize_guarded] Warning: Could not derive fallback for lhs '%s'", lhs), { title = "resize_guarded" })
  end

  -- Return the callback function that will be executed on keypress
  return function()
    -- Get current buffer information
    local buf = api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype or ""
    local name = api.nvim_buf_get_name(buf) or ""

    -- Check if buffer filetype is in exclusion list
    for _, ftype in ipairs(exclude_filetypes) do
      if ft == ftype then
        -- Buffer is excluded: forward the original key
        if fallback_seq then
          forward_key(fallback_seq)
        end
        return
      end
    end

    -- Check if buffer name matches any exclusion pattern
    for _, pat in ipairs(exclude_names) do
      if name:match(pat) then
        -- Buffer is excluded: forward the original key
        if fallback_seq then
          forward_key(fallback_seq)
        end
        return
      end
    end

    -- Buffer is not excluded: execute the resize command
    -- Use pcall to catch any errors from vim.cmd
    local ok, err = pcall(function() vim.cmd(cmd) end)
    if not ok then
      notify.error(string.format("[resize_guarded] Resize command failed: %s", err), { title = "resize_guarded" })
    end
  end
end

---@type Lib.BufWinTab.ResizeGuarded
return M
