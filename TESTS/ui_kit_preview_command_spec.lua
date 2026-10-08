-- TESTS/ui_kit_preview_command_spec.lua — when `:KitPreview` exists.
--
-- Requiring the kit registers nothing (LUA-92); the command appears once the
-- host calls `kit.setup()` or opens the playground through `kit.preview()`.
-- Every doc that mentions `:KitPreview` says exactly that, so this pins it:
-- a bare `require` must stay command-free, and the two documented ways to get
-- the command must keep registering it.

return function(H)
  local eq = H.eq

  local function is_kit(name)
    return name == "lib.nvim.ui.kit" or name:find("^lib%.nvim%.ui%.kit%.") ~= nil
  end

  -- Work on a fresh copy of the kit tree: an earlier spec has already called
  -- `setup()`, so the cached modules would prove nothing about a bare require.
  local saved = {}
  for name, mod in pairs(package.loaded) do
    if is_kit(name) then
      saved[name] = mod
    end
  end
  for name in pairs(saved) do
    package.loaded[name] = nil
  end
  pcall(vim.api.nvim_del_user_command, "KitPreview")

  local ok, err = pcall(function()
    local kit = require("lib.nvim.ui.kit")
    eq(vim.fn.exists(":KitPreview"), 0, "requiring the kit registers no :KitPreview")

    kit.setup()
    eq(vim.fn.exists(":KitPreview"), 2, "kit.setup() registers :KitPreview")

    -- The playground registers the command on the way, setup or not.
    pcall(vim.api.nvim_del_user_command, "KitPreview")
    require("lib.nvim.ui.kit.preview")._command_installed = nil
    eq(vim.fn.exists(":KitPreview"), 0, "the command is gone before the playground opens")

    local tabs = #vim.api.nvim_list_tabpages()
    kit.preview()
    eq(vim.fn.exists(":KitPreview"), 2, "kit.preview() registers :KitPreview on the way")
    if #vim.api.nvim_list_tabpages() > tabs then
      pcall(vim.cmd, "tabclose")
    end
  end)

  -- Put the cached modules back whatever happened above, and leave the command
  -- unregistered with the original preview module ready to register it again.
  pcall(vim.api.nvim_del_user_command, "KitPreview")
  for name in pairs(package.loaded) do
    if is_kit(name) then
      package.loaded[name] = nil
    end
  end
  for name, mod in pairs(saved) do
    package.loaded[name] = mod
  end
  local original = saved["lib.nvim.ui.kit.preview"]
  if original then
    original._command_installed = nil
  end

  if not ok then
    error(err, 0)
  end
end
