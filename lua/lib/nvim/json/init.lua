---@module 'lib.nvim.json'
--- Decode/encode arbitrary JSON strings (not just files — see
--- `lib.nvim.fs.json` for the file-backed counterpart this module now
--- backs). Decoding uses Neovim's built-in `vim.json.decode`:
--- `lib.lua.json` only exposes an encoder and array-shape decode
--- *helpers*, not a general JSON-string parser, and this module lives in
--- the `lib.nvim` (editor-adapter) namespace where `vim.json` is always
--- available. Encoding delegates to `lib.lua.json.encode`, the pure-Lua
--- encoder, so encoded output is identical inside and outside Neovim.
---
---```lua
--- local json = require("lib.nvim.json")
---
--- local tbl, err = json.decode('{"a":1}')
--- local str, err2 = json.encode({ a = 1 })
---```

require("lib.nvim.json.@types")

local lua_json = require("lib.lua.json")

local M = {}

---Decode a JSON string into a Lua value.
---@param str string
---@return any decoded
---@return string|nil err
function M.decode(str)
  local ok, decoded_or_err = pcall(vim.json.decode, str)
  if not ok then
    return nil, "invalid JSON: " .. tostring(decoded_or_err)
  end
  return decoded_or_err, nil
end

---JSON-encode `value`. Delegates to `lib.lua.json.encode`.
---@param value any
---@param opts? Lib.JSON.EncodeOpts
---@return string|nil encoded
---@return string|nil err
function M.encode(value, opts)
  return lua_json.encode(value, opts)
end

---@type Lib.Nvim.Json
return M
