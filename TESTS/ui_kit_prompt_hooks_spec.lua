-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_prompt_hooks_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_prompt_hooks_spec.lua (the kit exists twice, see ui.nvim's docs/modules.md): the
-- `TextChanged` hooks of a prompt belong to that prompt.
--
-- `kit.live_input` and `kit.compare` hung theirs under one fixed group name and asked for that
-- group with `clear`, so every new prompt cleared the hooks of the one that was already open:
-- `on_change` of the first (the query of the first compare) was never called again once a second
-- was opened -- the same bug `kit.input`'s re-mask had (see TESTS/ui_kit_conceal_spec.lua). The
-- hooks are buffer-local now and in no group; they go with the buffer, and they are not recorded.
--
-- Each block opens two of the same kind, types into the FIRST one and into the second, and waits
-- for each one's own callback: the hook fires through a debounce timer.

return function(H)
  local eq, ok = H.eq, H.ok
  local kit = require("lib.nvim.ui.kit")
  local autocmd = require("lib.nvim.bindings.autocmd")
  local api = vim.api

  --- Type `text` into the buffer the way a `TextChanged` sees it.
  ---@param bufnr integer
  ---@param text string
  local function type_into(bufnr, text)
    api.nvim_buf_set_lines(bufnr, 0, 1, false, { text })
    api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
  end

  --- Run `body`, then close every float again whatever happens inside it.
  ---@param name string
  ---@param body fun()
  local function section(name, body)
    local done, err = pcall(body)
    vim.cmd("stopinsert")
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
    if not done then
      error(("%s: %s"):format(name, tostring(err)), 0)
    end
  end

  section("two live_input prompts", function()
    local seen = { first = {}, second = {} }
    local first = kit.live_input({
      relative = "editor",
      debounce = 10,
      on_change = function(q)
        seen.first[#seen.first + 1] = q
      end,
    })
    local second = kit.live_input({
      relative = "editor",
      debounce = 10,
      on_change = function(q)
        seen.second[#seen.second + 1] = q
      end,
    })
    type_into(first.bufnr, "aaa")
    type_into(second.bufnr, "bbb")
    local landed = vim.wait(2000, function()
      return #seen.first > 0 and #seen.second > 0
    end, 10)
    ok(landed, "both were called: " .. vim.inspect(seen))
    eq(
      table.concat(seen.first, ","),
      "aaa",
      "the first prompt, whose hooks the second used to clear"
    )
    eq(table.concat(seen.second, ","), "bbb", "the second prompt")
  end)

  section("live_input records", function()
    local before = #autocmd.registered()
    for _ = 1, 3 do
      kit.live_input({ relative = "editor", on_change = function() end }):close()
    end
    eq(#autocmd.registered(), before, "the hook is no recorded autocmd")
  end)

  --- A compare whose query function is `queries`' recorder: it runs when the prompt's text
  --- changed and the debounce ran out.
  ---@param queries string[]
  ---@return table handle
  local function open_compare(queries)
    return kit.compare({
      items = { "alpha", "beta" },
      render = function(item, surf)
        surf:set_lines({ item })
      end,
      query = function(q, items)
        queries[#queries + 1] = q
        return items
      end,
    })
  end

  section("two compare pickers", function()
    local seen = { first = {}, second = {} }
    local first = open_compare(seen.first)
    local second = open_compare(seen.second)
    type_into(first.slots().prompt.bufnr, "aaa")
    type_into(second.slots().prompt.bufnr, "bbb")
    -- The debounce is 80 ms and not an option.
    local landed = vim.wait(3000, function()
      return #seen.first > 0 and #seen.second > 0
    end, 10)
    ok(landed, "both were called: " .. vim.inspect(seen))
    eq(
      table.concat(seen.first, ","),
      "aaa",
      "the first compare, whose hooks the second used to clear"
    )
    eq(table.concat(seen.second, ","), "bbb", "the second compare")
  end)

  section("compare after the first pick", function()
    -- SEARCH -> MARKED mounts a new prompt buffer: the hook has to be on that one.
    local queries = {}
    local compare = open_compare(queries)
    compare.mark()
    eq(compare.state(), "marked", "the first pick is marked")
    type_into(compare.slots().prompt.bufnr, "zzz")
    local landed = vim.wait(3000, function()
      return #queries > 0
    end, 10)
    ok(landed, "the marked state re-ran the query")
    eq(table.concat(queries, ","), "zzz", "with what was typed there")
  end)

  section("compare records", function()
    local before = #autocmd.registered()
    for _ = 1, 3 do
      local compare = open_compare({})
      compare.mark()
      compare.close()
    end
    eq(#autocmd.registered(), before, "the hook is no recorded autocmd")
  end)
end
