-- TESTS/ui_kit_lazy_spec.lua -- `require("lib.nvim.ui.kit")` loads no component: they come in on first use, and
-- every public field and function is still reachable. A fresh child editor, since this process has loaded them all.

return function(H)
  local eq, ok = H.eq, H.ok
  local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
  local script = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({
    "vim.opt.rtp:prepend(" .. vim.inspect(repo) .. ")",
    'local kit = require("lib.nvim.ui.kit")',
    "local eager = {}",
    "for name in pairs(package.loaded) do",
    '  if name:find("^lib%.nvim%.ui%.kit%.") and name ~= "lib.nvim.ui.kit.@types" then',
    "    eager[#eager + 1] = name",
    "  end",
    "end",
    "table.sort(eager)",
    "local missing = {}",
    'for _, name in ipairs({ "setup", "popup", "note", "viewer", "message_log", "toast", "input", "live_input", "form",',
    '  "sheet", "select", "prompt", "picker", "shortlist", "confirm", "set_dialog_hook", "get_dialog_hook", "ask",',
    '  "menu", "compare", "progress", "async", "preview", "surface", "theme", "layout", "chooser", "chip",',
    '  "keys", "history", "create_on_missing", "sidebar" }) do',
    "  if kit[name] == nil then",
    "    missing[#missing + 1] = name",
    "  end",
    "end",
    "local surface_open = type(kit.surface.open)",
    "print(vim.json.encode({",
    "  eager = eager,",
    "  missing = missing,",
    "  surface_open = surface_open,",
    '  loaded_after = package.loaded["lib.nvim.ui.kit.surface"] ~= nil,',
    "}))",
    'vim.cmd("qa!")',
  }, script)
  local r = vim
    .system(
      { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", script },
      { text = true }
    )
    :wait(30000)
  vim.fn.delete(script)
  local out = (r.stdout or "") .. (r.stderr or "")
  local json = out:match("(%b{})")
  ok(json ~= nil, "the child answered: " .. out:sub(1, 300))
  local got = vim.json.decode(json, { luanil = { object = true, array = true } })
  eq(
    #(got.eager or {}),
    0,
    "requiring the kit loads no component: " .. table.concat(got.eager or {}, ",")
  )
  eq(
    #(got.missing or {}),
    0,
    "every public field and function is reachable: " .. table.concat(got.missing or {}, ",")
  )
  eq(got.surface_open, "function", "a module field (kit.surface) loads on first access")
  eq(got.loaded_after, true, "...and is loaded then")
end
