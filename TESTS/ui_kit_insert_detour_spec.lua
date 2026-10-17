-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_insert_detour_spec.lua -- a read-only float opened from an
-- Insert-mode key, and the way back into the picker prompt it was opened from.
--
-- Entering a window keeps the mode. A `kit.viewer` opened by a picker's caller key
-- (bound in Insert and Normal mode, the prompt starts in Insert mode) stood in
-- Insert mode: `q` was typed (E21) instead of closing it. And once it was closed,
-- the prompt stood in Normal mode, so the next letter was a command (`x` deleted)
-- instead of going into the query.
--
-- The shared headless run never enters Insert mode (see ui_kit_insert_chain_spec),
-- so this spec drives an embedded child Neovim over RPC: `nvim_input` feeds real
-- keys, and every query is an `nvim_exec_lua` request, which the child handles only
-- once the keys before it have been processed.

return function(H)
  local eq = H.eq

  local spec_dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
  local root = vim.fs.normalize(vim.fn.fnamemodify(spec_dir .. "..", ":p"))

  local chan = vim.fn.jobstart(
    { vim.v.progpath, "-n", "-i", "NONE", "-u", "NONE", "--embed", "--headless" },
    { rpc = true }
  )
  assert(chan > 0, "could not start an embedded Neovim: " .. tostring(chan))

  local function lua(code, ...)
    return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
  end
  local function input(keys)
    vim.rpcrequest(chan, "nvim_input", keys)
  end

  local done, err = pcall(function()
    lua("vim.opt.rtp:append(...)", root)
    lua([[
      vim.o.showmode = false
      local kit = require("lib.nvim.ui.kit")
      local viewer = require("lib.nvim.ui.kit.viewer")
      local api = vim.api

      --- Open a picker whose caller keys open a viewer (`<C-v>`), a viewer after the
      --- caller ended Insert mode itself (`<C-s>`), a float that is typed into (`<C-e>`) and
      --- a compare (`<C-k>`), whose helper panes are entered on the way to its prompt.
      function _G.detour_open()
        for _, w in ipairs(api.nvim_list_wins()) do
          if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
            pcall(api.nvim_win_close, w, true)
          end
        end
        _G.V = nil
        _G.P = kit.picker({
          items = { "alpha", "beta", "gamma" },
          on_submit = function() end,
          keys = {
            ["<C-v>"] = function()
              _G.V = viewer.open({ lines = { "details" } })
            end,
            ["<C-s>"] = function()
              vim.cmd("stopinsert")
              _G.V = viewer.open({ lines = { "details" } })
            end,
            ["<C-e>"] = function()
              _G.V = require("lib.nvim.ui.kit.surface").open({
                lines = { "" },
                modifiable = true,
                width = 20,
                height = 1,
              })
            end,
            ["<C-k>"] = function()
              kit.compare({
                items = { "a", "b" },
                render = function(item, surface)
                  surface:set_lines({ item })
                end,
              })
            end,
          },
        })
      end

      function _G.detour_state()
        local win = api.nvim_get_current_win()
        return {
          mode = api.nvim_get_mode().mode,
          in_prompt = win == _G.P.slots.prompt.winid,
          in_viewer = _G.V ~= nil and win == _G.V.winid,
          viewer_open = _G.V ~= nil and api.nvim_win_is_valid(_G.V.winid),
          query = _G.P.query(),
          col = api.nvim_win_get_cursor(0)[2],
        }
      end
    ]])
    local function open()
      input("<C-\\><C-n>") -- out of whatever mode the earlier case left
      lua("_G.detour_open()")
      input("<Ignore>")
    end
    local function state()
      return lua("return _G.detour_state()")
    end

    -- The picker itself starts in Insert mode (the baseline everything below relies on).
    open()
    local s = state()
    eq(s.in_prompt, true, "the picker opens in its prompt")
    eq(s.mode, "i", "the picker prompt starts in Insert mode")

    -- A viewer opened from the Insert-mode key stands in Normal mode ...
    input("<C-v>")
    s = state()
    eq(s.in_viewer, true, "the caller key focused the viewer")
    eq(s.mode, "n", "a read-only viewer opened from Insert mode is in Normal mode")
    -- ... so `q` closes it on the first press ...
    input("q")
    s = state()
    eq(s.viewer_open, false, "q closes the viewer on the first press")
    eq(s.in_prompt, true, "closing the viewer returns to the prompt")
    -- ... and the prompt is back in Insert mode: the next letter filters.
    eq(s.mode, "i", "back in the prompt, back in Insert mode")
    input("x")
    eq(state().query, "x", "the next letter goes into the query")

    -- `<Esc>` closes the viewer on the first press too.
    open()
    input("<C-v>")
    input("<Esc>")
    s = state()
    eq(s.viewer_open, false, "<Esc> closes the viewer on the first press")
    eq(s.mode, "i", "<Esc> on the viewer leaves the prompt in Insert mode")
    input("y")
    eq(state().query, "y", "after <Esc> the next letter goes into the query")

    -- Insert mode resumes where it was, not at the end of the line.
    open()
    input("ab<Left>")
    eq(state().col, 1, "the cursor stands between a and b")
    input("<C-v>")
    input("q")
    input("x")
    eq(state().query, "axb", "typing resumes at the column Insert mode had")

    -- At the end of the query it resumes after the last letter (not before it).
    open()
    input("ab")
    input("<C-v>")
    input("q")
    input("c")
    eq(state().query, "abc", "at the end of the query typing appends")

    -- A caller that ends Insert mode itself before opening the viewer: same way back.
    open()
    input("<C-s>")
    s = state()
    eq(s.mode, "n", "the caller's own :stopinsert also lands the viewer in Normal mode")
    input("q")
    input("z")
    s = state()
    eq(s.mode, "i", "the prompt is back in Insert mode after the caller's own :stopinsert")
    eq(s.query, "z", "and the next letter goes into the query")

    -- Left from Normal mode, the prompt is given back in Normal mode.
    open()
    input("<C-\\><C-n>")
    eq(state().mode, "n", "the prompt is in Normal mode")
    input("<C-v>")
    input("q")
    s = state()
    eq(s.in_prompt, true, "the viewer closed back into the prompt")
    eq(s.mode, "n", "a prompt left from Normal mode is not put into Insert mode")

    -- A float that is typed into keeps Insert mode.
    open()
    input("<C-e>")
    s = state()
    eq(s.in_viewer, true, "the caller key focused the modifiable float")
    eq(s.mode, "i", "a modifiable float opened from Insert mode stays in Insert mode")

    -- A compare enters its read-only helper panes on the way (the default `enter`) and
    -- ends up in its prompt, in Insert mode: those panes must not end it.
    open()
    input("<C-k>")
    s = state()
    eq(s.in_prompt, false, "the compare took the focus")
    eq(
      lua("return vim.bo.filetype"),
      "lib-kit-compare-prompt",
      "the focus is in the compare's prompt"
    )
    eq(s.mode, "i", "a compare opened from Insert mode is in Insert mode")
  end)

  pcall(vim.fn.jobstop, chan)
  assert(done, err)
end
