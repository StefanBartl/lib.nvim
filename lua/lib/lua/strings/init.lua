---@module 'lib.lua.strings'
--- Aggregator for lib.lua's pure-Lua string helpers: case conversion,
--- padding, trimming, splitting/joining, and other string utilities.

local M = {}

M.remove_prefix = require("lib.lua.strings.remove_prefix")
-- core module
M.trim = require("lib.lua.strings.core").trim
M.slugify = require("lib.lua.strings.core").slugify
M.kebab_case = require("lib.lua.strings.core").kebab_case
M.starts_with = require("lib.lua.strings.core").starts_with
M.ends_with = require("lib.lua.strings.core").ends_with
M.contains = require("lib.lua.strings.core").contains
M.split = require("lib.lua.strings.core").split
M.join = require("lib.lua.strings.core").join
M.replace_all = require("lib.lua.strings.core").replace_all
M.normalize_ws = require("lib.lua.strings.core").normalize_ws
M.capitalize = require("lib.lua.strings.core").capitalize
M.uncapitalize = require("lib.lua.strings.core").uncapitalize
M.snake_case = require("lib.lua.strings.core").snake_case
M.camel_case = require("lib.lua.strings.core").camel_case
M.pad_start = require("lib.lua.strings.core").pad_start
M.pad_end = require("lib.lua.strings.core").pad_end
M.pad_center = require("lib.lua.strings.core").pad_center
M.indent = require("lib.lua.strings.core").indent
M.dedent = require("lib.lua.strings.core").dedent
M.is_empty_or_space = require("lib.lua.strings.core").is_empty_or_space
M.count_lines = require("lib.lua.strings.core").count_lines

-- patterns module
M.escape_lua_magic = require("lib.lua.strings.patterns").escape_lua_magic
M.find_plain = require("lib.lua.strings.patterns").find_plain
M.replace_plain = require("lib.lua.strings.patterns").replace_plain
M.surround = require("lib.lua.strings.patterns").surround
M.strip_ansi = require("lib.lua.strings.patterns").strip_ansi

-- links module
M.uri_decode = require("lib.lua.strings.links").uri_decode
M.normalize_anchor = require("lib.lua.strings.links").normalize_anchor
--- CDX: `lib.lua.strings.links` has no `normalize_ws`, so this line sets
--- CDX: `M.normalize_ws` back to nil, clobbering the working `core.normalize_ws`
--- CDX: assigned above — despite `Lib.Strings.normalize_ws` being a declared type.
M.normalize_ws = require("lib.lua.strings.links").normalize_ws
M.has_scheme = require("lib.lua.strings.links").has_scheme
M.is_web_url = require("lib.lua.strings.links").is_web_url
M.url_under_cursor = require("lib.lua.strings.links").url_under_cursor

-- utf8 module
M.utf8_char_len = require("lib.lua.strings.utf8").char_len
M.utf8_encode = require("lib.lua.strings.utf8").encode
M.utf8_decode = require("lib.lua.strings.utf8").decode
M.utf8_iter = require("lib.lua.strings.utf8").iter

-- encoding module
M.url_encode = require("lib.lua.strings.encoding").url_encode
M.url_decode = require("lib.lua.strings.encoding").url_decode
M.base64_encode = require("lib.lua.strings.encoding").base64_encode
M.base64_decode = require("lib.lua.strings.encoding").base64_decode
M.html_escape = require("lib.lua.strings.encoding").html_escape

-- distance module
M.levenshtein = require("lib.lua.strings.distance").levenshtein
M.similarity = require("lib.lua.strings.distance").similarity

-- format module
M.format_bytes = require("lib.lua.strings.format").format_bytes
M.format_number = require("lib.lua.strings.format").format_number

-- location module
M.parse_location = require("lib.lua.strings.location").parse_location

-- case module
M.case_shape = require("lib.lua.strings.case").case_shape
M.apply_shape = require("lib.lua.strings.case").apply_shape
M.change_case = require("lib.lua.strings.case").change_case

-- wrap module
M.center_text = require("lib.lua.strings.wrap").center_text
M.center_text_lines = require("lib.lua.strings.wrap").center_text_lines

-- width module
-- Only the three functions with no byte-based counterpart are flattened
-- onto the aggregator. `width.pad_start`/`pad_end`/`pad_center` are NOT:
-- those names already belong to the byte-based `core` versions above, and
-- silently swapping their semantics here would change existing callers'
-- output for any non-ASCII input. Reach them through `M.width` instead.
M.char_width = require("lib.lua.strings.width").char_width
M.display_width = require("lib.lua.strings.width").display_width
M.truncate = require("lib.lua.strings.width").truncate

M.width = require("lib.lua.strings.width")

---@type Lib.Strings
return M
