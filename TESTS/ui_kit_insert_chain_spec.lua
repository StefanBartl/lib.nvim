-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_insert_chain_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_insert_chain_spec.lua (the kit exists twice, see ui.nvim's
-- docs/modules.md): which window a closing prompt leaves in Insert mode.
--
-- A prompt that closes calls `:stopinsert` -- unless a callback has just opened
-- the next window to be typed into, whose own `:startinsert` is ignored while the
-- closing one's Insert mode is still on (that window would then stand in Normal
-- mode, the first thing typed a command). This shared headless run never enters
-- Insert mode, so what is pinned here is the decision: whether `:stopinsert` is
-- called, and who counts as "opened a window to type into" (`input.mark_opened`).

return function(H)
  local eq = H.eq
  local kit = require("lib.nvim.ui.kit")
  local input = require("lib.nvim.ui.kit.input")
  local api = vim.api

  vim.o.showmode = false

  local function keys(k)
    api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "x", false)
  end

  local function close_floats()
    for _ = 1, 10 do
      local closed = false
      for _, w in ipairs(api.nvim_list_wins()) do
        -- Closing one window can close others (a picker is several): look before touching.
        if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
          pcall(api.nvim_win_close, w, true)
          closed = true
        end
      end
      if not closed then
        return
      end
    end
  end

  --- Run `body` and say how often `:stopinsert` was asked for meanwhile.
  ---@param body fun()
  ---@return integer
  local function count_stopinsert(body)
    local stops = 0
    local real_cmd = vim.cmd
    vim.cmd = setmetatable({}, {
      __call = function(_, c, ...)
        if c == "stopinsert" then
          stops = stops + 1
        end
        return real_cmd(c, ...)
      end,
      __index = real_cmd,
    })
    local ok, err = pcall(body)
    vim.cmd = real_cmd
    assert(ok, err)
    return stops
  end

  local done, err = pcall(function()
    -- Every component that is typed into counts itself.
    local before = input.opened_count()
    kit.input({})
    eq(input.opened_count(), before + 1, "a prompt is counted")
    kit.sheet({ fields = { { name = "a" } }, on_submit = function() end })
    eq(input.opened_count(), before + 2, "a sheet is counted")
    kit.picker({ on_change = function() end, on_submit = function() end })
    eq(input.opened_count(), before + 3, "a picker is counted")
    kit.live_input({ on_change = function() end })
    eq(input.opened_count(), before + 4, "a live_input is counted")
    kit.compare({
      items = { "a", "b" },
      render = function(item, surface)
        surface:set_lines({ item })
      end,
    })
    eq(input.opened_count(), before + 5, "a compare is counted")
    require("lib.nvim.ui.kit.select").open({ items = { "a" }, on_select = function() end })
    require("lib.nvim.ui.kit.confirm").open({ question = "?" })
    eq(input.opened_count(), before + 5, "a chooser and a confirm are not")
    close_floats()

    -- A prompt that closes under each of them keeps Insert mode.
    local openers = {
      ["a sheet"] = function()
        kit.sheet({ fields = { { name = "a" } }, on_submit = function() end })
      end,
      ["a picker"] = function()
        kit.picker({ on_change = function() end, on_submit = function() end })
      end,
      ["a live_input"] = function()
        kit.live_input({ on_change = function() end })
      end,
      ["a compare"] = function()
        kit.compare({
          items = { "a", "b" },
          render = function(item, surface)
            surface:set_lines({ item })
          end,
        })
      end,
      ["another prompt"] = function()
        kit.input({})
      end,
    }
    for name, open_next in pairs(openers) do
      local stops = count_stopinsert(function()
        kit.input({ on_submit = open_next })
        keys("<CR>")
      end)
      eq(stops, 0, "a prompt closing under " .. name .. " does not stop Insert mode")
      close_floats()
    end

    -- ... and stops it when nothing typed into was opened.
    local answered
    local stops = count_stopinsert(function()
      kit.input({
        on_submit = function(v)
          answered = v
        end,
      })
      keys("<CR>")
    end)
    eq(answered, "", "the prompt answered")
    eq(stops, 1, "Insert mode ends with a prompt that opens nothing")
    stops = count_stopinsert(function()
      kit.input({
        on_submit = function()
          require("lib.nvim.ui.kit.select").open({
            items = { "a", "b" },
            on_select = function() end,
          })
        end,
      })
      keys("<CR>")
    end)
    eq(stops, 1, "a chooser is driven from Normal mode")
    close_floats()

    -- The sheet after the last field of a form.
    stops = count_stopinsert(function()
      kit.form({
        fields = { { name = "a" } },
        on_submit = function()
          kit.sheet({ fields = { { name = "b" } }, on_submit = function() end })
        end,
      })
      keys("<CR>")
    end)
    eq(stops, 0, "the sheet that follows the last field of a form keeps Insert mode")
    close_floats()

    -- A sheet that closes over a modifiable float that was there before: the
    -- focus goes back to a window that waits for nothing, so Insert mode ends.
    for _, leave in ipairs({ "<Esc>", "<CR>" }) do
      local origin_buf = api.nvim_create_buf(false, true)
      api.nvim_open_win(
        origin_buf,
        true,
        { relative = "editor", row = 2, col = 2, width = 20, height = 3 }
      )
      local origin = api.nvim_get_current_win()
      kit.sheet({
        fields = { { name = "a" } },
        on_submit = function() end,
        on_cancel = function() end,
      })
      stops = count_stopinsert(function()
        keys(leave)
      end)
      eq(api.nvim_get_current_win(), origin, "the focus is back in the float (" .. leave .. ")")
      eq(stops, 1, "a sheet closing over a float stops Insert mode (" .. leave .. ")")
      close_floats()
    end
  end)

  close_floats()
  assert(done, err)
end
