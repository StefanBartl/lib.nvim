-- templates/contract_host.lua -- copy to `scripts/<plugin>-host.lua` of a plugin that speaks a machine contract.
--
--   nvim --headless -u NONE -i NONE -n -l scripts/<plugin>-host.lua
--
-- The persistent engine: answers the contract over stdin and stdout (the line protocol is documented in
-- `lua/lib/nvim/contract/host/README.md`). The process ends when its stdin ends, so a client that dies never leaves
-- it behind. The source and the switches come from the environment, as for the plugin's command line.
--
-- Replace the two names below, nothing else:
--   MODULE   the Lua module that returns `require("lib.nvim.contract.host").make({ api = api })`, e.g. "rules_nvim.host"
--   PLUGIN   the plugin's folder name, only for the message, e.g. "rules.nvim"
--
-- Why this is a copy and not a module of lib.nvim: the script runs BEFORE lib.nvim is on the runtimepath (`-u NONE`
-- loads no plugin manager), so it cannot `require` anything of it to find it.
local MODULE = "your_plugin.host"
local PLUGIN = "your-plugin.nvim"

-- Absolute: `nvim -l` from inside scripts/ gives a bare relative name.
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(script)))

---A path as ONE runtimepath entry: 'runtimepath' is a comma list, so a comma in a folder name must be escaped or the
---path is split in two, the second half a relative entry that is looked up in whatever folder the client started in.
---@param path string
---@return string
local function rtp_entry(path)
  return (vim.fn.escape(path, ","))
end

vim.opt.rtp:prepend(rtp_entry(plugin_root))

---@param dir string|nil
---@return boolean
local function has_lib(dir)
  return dir ~= nil and dir ~= "" and vim.fn.isdirectory(dir .. "/lua/lib/nvim") == 1
end

---The checkout of lib.nvim: `$LIB_NVIM_DIR`, `$LIB_NVIM_PATH`, `$REPOS_DIR/lib.nvim`, `.deps/lib.nvim` of the plugin, a
---sibling checkout, then lazy.nvim's data folder.
---@return string|nil
local function find_lib()
  local repos = vim.env.REPOS_DIR
  -- Not a list literal: `ipairs` would stop at the first unset variable.
  local candidates = {
    LIB_NVIM_DIR = vim.env.LIB_NVIM_DIR,
    LIB_NVIM_PATH = vim.env.LIB_NVIM_PATH,
    REPOS_DIR = (repos and repos ~= "") and (repos .. "/lib.nvim") or nil,
    deps = plugin_root .. "/.deps/lib.nvim",
    sibling = vim.fs.dirname(plugin_root) .. "/lib.nvim",
    lazy = vim.fn.stdpath("data") .. "/lazy/lib.nvim",
  }
  for _, key in ipairs({ "LIB_NVIM_DIR", "LIB_NVIM_PATH", "REPOS_DIR", "deps", "sibling", "lazy" }) do
    if has_lib(candidates[key]) then
      return candidates[key]
    end
  end
  return nil
end

local lib = find_lib()
if not lib then
  io.stderr:write(
    ("error: lib.nvim not found for %s (set LIB_NVIM_DIR, or REPOS_DIR with a lib.nvim checkout)\n"):format(
      PLUGIN
    )
  )
  os.exit(2)
end
vim.opt.rtp:append(rtp_entry(lib))

require(MODULE).serve(io.stdin, io.stdout)
io.stdout:flush()
os.exit(0)
