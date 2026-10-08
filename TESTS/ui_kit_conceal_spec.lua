-- Test code: when something here comes back nil, this file must crash and
-- name it rather than silently skip -- see TESTS/ui_kit_spec.lua's header.
---@diagnostic disable: need-check-nil
-- TESTS/ui_kit_conceal_spec.lua -- lib.nvim.ui.kit's copy of ui.nvim's
-- TESTS/ui_kit_conceal_spec.lua (the kit exists twice, see ui.nvim's
-- docs/modules.md): `input.conceal_line`, the mask over a secret's characters, in
-- linear time. It used to walk the line with `byteidx(line, i)` for every
-- character, and each call rescans the line from its start: quadratic (30 000
-- characters took about nine seconds). The marks it sets are the same ones: one per
-- character, a base character and its combining marks counting as one.

return function(H)
  local eq, ok = H.eq, H.ok
  local input = require("lib.nvim.ui.kit.input")
  local api = vim.api
  local fn = vim.fn

  --- What the old walk produced, as `start-end` byte ranges: the reference.
  ---@param line string
  ---@return string
  local function reference(line)
    local out = {}
    for i = 0, fn.strchars(line) - 1 do
      local s, e = fn.byteidx(line, i), fn.byteidx(line, i + 1)
      if s >= 0 and e >= s then
        out[#out + 1] = s .. "-" .. e
      end
    end
    return table.concat(out, ",")
  end

  --- Mask `line` in a scratch buffer: the marks set as `start-end` ranges, and whether
  --- every one carries `mask`.
  ---@param line string
  ---@param mask? string
  ---@return string ranges
  ---@return boolean all_masked
  local function masked(line, mask)
    mask = mask or "*"
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    local ns = api.nvim_create_namespace("lib_kit_conceal_spec")
    input.conceal_line(buf, ns, 0, mask)
    local marks = api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    table.sort(marks, function(a, b)
      return a[3] < b[3]
    end)
    local out, all = {}, true
    for _, m in ipairs(marks) do
      out[#out + 1] = m[3] .. "-" .. m[4].end_col
      all = all and m[4].conceal == mask
    end
    api.nvim_buf_delete(buf, { force = true })
    return table.concat(out, ","), all
  end

  local ranges, all = masked("abc")
  eq(ranges, "0-1,1-2,2-3", "one mark per character")
  ok(all, "each one carries the mask")
  eq((masked("aé漢😀z")), "0-1,1-3,3-6,6-10,10-11", "one to four bytes")
  eq((masked("")), "", "an empty line has nothing to hide")
  eq((masked("é", "•")), "0-2", "a custom mask")

  -- A base character and its combining marks sit under one mark.
  eq((masked("e\204\129x")), "0-3,3-4", "e + U+0301, then x")
  eq((masked("x\204\129\204\130y")), "0-5,5-6", "two marks on one base")
  eq((masked("\226\157\164\239\184\143a")), "0-6,6-7", "a heart and its variation selector")

  -- The marks the byteidx() walk set, for any valid text.
  local pieces = {
    "a",
    "é",
    "e\204\129",
    "漢",
    "😀",
    "\226\157\164\239\184\143",
    "👍\240\159\143\189",
    "🇩🇪",
    "x\204\129\204\130",
    " ",
    "ß",
  }
  math.randomseed(20261007)
  for _ = 1, 300 do
    local parts = {}
    for i = 1, math.random(0, 12) do
      parts[i] = pieces[math.random(#pieces)]
    end
    local s = table.concat(parts)
    eq((masked(s)), reference(s), ("the old marks for %q"):format(s))
  end

  -- Every byte of text that is not valid UTF-8 is under a mark too.
  for _, s in ipairs({ "a\255b", "\226\130x", "\192\128", "\255\204\129" }) do
    local covered = 0
    for from, to in masked(s):gmatch("(%d+)-(%d+)") do
      eq(tonumber(from), covered, "no gap before " .. from .. " in " .. ("%q"):format(s))
      covered = tonumber(to)
    end
    eq(covered, #s, "every byte of " .. ("%q"):format(s) .. " is under a mark")
  end

  -- Time in proportion to the line, not its square.
  local line = string.rep("pässwörd漢", 3333)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local ns = api.nvim_create_namespace("lib_kit_conceal_spec_perf")
  local t0 = vim.uv.hrtime()
  input.conceal_line(buf, ns, 0, "*")
  local ms = (vim.uv.hrtime() - t0) / 1e6
  local count = #api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  api.nvim_buf_delete(buf, { force = true })
  eq(count, 29997, "one mark per character of a long line")
  ok(ms < 1500, ("masking 30 000 characters took %.0f ms"):format(ms))

  -- A NUL byte in text that goes through `vim.fn`. A NUL in a Lua string reaches it as a
  -- Blob, and `split()` or `strdisplaywidth()` raise E976 on it. The mask is re-applied from
  -- a `TextChanged` handler that clears its namespace first: a raise there left every
  -- character of the secret unmasked, on screen. A NUL gets into a prompt by a paste or
  -- `<C-v>000`, or through `default`; a title is measured when the prompt opens.
  local nul = string.char(0)
  local nul_ok, nul_ranges, nul_all = pcall(masked, "abc" .. nul .. "def")
  ok(nul_ok, "conceal_line does not raise on a NUL: " .. tostring(nul_ranges))
  eq(nul_ranges, "0-1,1-2,2-3,3-4,4-5,5-6,6-7", "one mark per character, the NUL included")
  ok(nul_all, "each one carries the mask")
  eq((masked("e\204\129" .. nul)), "0-3,3-4", "a base with its combining mark, then the NUL")

  local kit = require("lib.nvim.ui.kit")
  local surfaces = {}
  local nul_done, nul_err = pcall(function()
    local surf = kit.input({ secret = true, relative = "editor" })
    surfaces[#surfaces + 1] = surf
    local secret_ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    local function marks()
      return #api.nvim_buf_get_extmarks(surf.bufnr, secret_ns, 0, -1, {})
    end
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "abcdef" })
    api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
    eq(marks(), 6, "six characters, six marks")
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "abc" .. nul .. "def" })
    api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
    eq(marks(), 7, "the NUL is masked as well, and the rest still is")

    local defaulted = kit.input({ secret = true, default = "a" .. nul .. "b", relative = "editor" })
    surfaces[#surfaces + 1] = defaulted
    local default_ns = api.nvim_create_namespace("lib_kit_input_secret_" .. defaulted.bufnr)
    eq(#api.nvim_buf_get_extmarks(defaulted.bufnr, default_ns, 0, -1, {}), 3, "a default: masked")

    local titled = kit.input({ title = "case" .. nul .. "title", relative = "editor" })
    ok(titled ~= nil, "a title with a NUL opens a prompt")
    surfaces[#surfaces + 1] = titled
  end)
  for _, surf in ipairs(surfaces) do
    pcall(surf.close, surf)
  end
  assert(nul_done, nul_err)

  -- `opts.mask` is text for `conceal`, and anything else is the default. A number, `true` or a
  -- table (a value handed on from a config) went to `nvim_buf_set_extmark` as it was: it raised
  -- "Invalid 'conceal': Expected Lua string" -- out of `open()` itself for a prompt with a
  -- default, with the window already open and no key mapped, and out of the `TextChanged`
  -- handler for one without, after `apply_mask` had cleared the marks. The password stood on
  -- screen, with an error for every key. `kit.sheet` already took a string only.
  local mask_surfaces = {}
  --- The text each mark on the prompt's line conceals with.
  local function conceals_of(surf)
    local mask_ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    local out = {}
    for _, m in ipairs(api.nvim_buf_get_extmarks(surf.bufnr, mask_ns, 0, -1, { details = true })) do
      out[#out + 1] = m[4].conceal
    end
    return out
  end
  --- What the marks of `surf` conceal with has to be `expected`.
  local function conceals(surf, expected, label)
    local got = conceals_of(surf)
    ok(vim.deep_equal(got, expected), label .. ": got " .. vim.inspect(got))
  end
  local mask_done, mask_err = pcall(function()
    for label, bad in pairs({ number = 5, boolean = true, table = {} }) do
      local opened, surf = pcall(kit.input, {
        secret = true,
        mask = bad,
        default = "hunter2",
        relative = "editor",
      })
      ok(opened, "a " .. label .. " mask: the prompt opens instead of raising: " .. tostring(surf))
      mask_surfaces[#mask_surfaces + 1] = surf
      conceals(surf, vim.fn["repeat"]({ "*" }, 7), "a " .. label .. " mask: the default's")
      api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "hunter22" })
      api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
      conceals(surf, vim.fn["repeat"]({ "*" }, 8), "a " .. label .. " mask: while typing")
    end

    local empty = kit.input({ secret = true, mask = 5, relative = "editor" })
    mask_surfaces[#mask_surfaces + 1] = empty
    api.nvim_buf_set_lines(empty.bufnr, 0, -1, false, { "hunter2" })
    api.nvim_exec_autocmds("TextChanged", { buffer = empty.bufnr })
    conceals(empty, vim.fn["repeat"]({ "*" }, 7), "typing into an empty prompt")

    local chosen = kit.input({ secret = true, mask = "•", default = "abc", relative = "editor" })
    mask_surfaces[#mask_surfaces + 1] = chosen
    conceals(chosen, { "•", "•", "•" }, "a string the caller chose")
    local blank = kit.input({ secret = true, mask = "", default = "abc", relative = "editor" })
    mask_surfaces[#mask_surfaces + 1] = blank
    conceals(blank, { "", "", "" }, "an empty string is a string: the characters are hidden")
  end)
  for _, surf in ipairs(mask_surfaces) do
    pcall(surf.close, surf)
  end
  assert(mask_done, mask_err)
end
