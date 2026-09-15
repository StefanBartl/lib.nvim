---@module 'lib.lua.xml'
--- Aggregator for lib.lua's pure-Lua XML decode/encode helpers. See
--- `decode.lua`/`encode.lua` for the exact (deliberately minimal) subset
--- supported and the shared element-tree shape both work against.
---
---   local xml = require("lib.lua.xml")
---   local tree, err = xml.decode('<a id="1">hi</a>')
---   local text, err2 = xml.encode(tree)

local M = {}

---@type Lib.Xml.Decode
M.decode = require("lib.lua.xml.decode").decode

-- Callable module: `xml.encode(value)` and `xml.encode.pretty(value)`.
---@type Lib.Xml.Encode
M.encode = require("lib.lua.xml.encode")

---@type LibXml
return M
