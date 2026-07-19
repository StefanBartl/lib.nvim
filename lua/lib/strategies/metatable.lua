---@module 'lib.strategies.metatable'
--- Ultra-lazy aggregator using metatable-based module proxy.
--- Nothing is loaded until first access.

---@type Lib
local LIB = {}

-- ============================================================================
-- Module Registry
-- ============================================================================

local MODULE_MAP = {
  -- NVIM
  simple_echo = "lib.nvim.core.simple_echo",

  -- CROSS-PLATFORM
  is_windows = "lib.nvim.cross.platform.is_windows",
  is_wsl = "lib.nvim.cross.platform.is_wsl",
  is_macos = "lib.nvim.cross.platform.is_macos",
  is_linux = "lib.nvim.cross.platform.is_linux",
  is = "lib.nvim.cross.platform.is",
  copy_to_clipboard = "lib.nvim.cross.copy_to_clipboard",
  run_argv = "lib.nvim.cross.run_argv",

  -- FILESYSTEM
  is_subpath = "lib.nvim.fs.is_subpath",
  is_dir = "lib.nvim.fs.is_dir",
  relpath = "lib.nvim.fs.relpath",
  find_upward_dir = "lib.nvim.fs.find_upward_dir",
  find_root = "lib.nvim.fs.find_root",
  mkdirp = "lib.nvim.fs.mkdirp",
  path_shorten = "lib.nvim.fs.path_shorten",
  write_to_file = "lib.nvim.fs.write.to_file",
  write_append = "lib.nvim.fs.write.append",

  -- BUFFER
  is_markdown_buf = "lib.nvim.buffer.is_markdown_buf",
  insert_lines = "lib.nvim.buffer.insert_lines",
  buffer_context = "lib.nvim.buffer.context",

  -- WINDOW
  window_context = "lib.nvim.window.context",

  -- CACHE (disk + memory)
  cache = "lib.nvim.cache",

  -- UI
  hl = "lib.nvim.ui.hl",
  kit = "lib.nvim.ui.kit",

  -- AUTOCMD/KEYMAP
  autocmd = "lib.nvim.autocmd",
  map = "lib.nvim.map",
  usercmd = "lib.nvim.usercmd",
  composer = "lib.nvim.usercmd.composer",

  -- NOTIFY
  notify = "lib.nvim.notify",
  resolve_log_level = "lib.nvim.notify.resolve_log_level",

  -- LOGGER
  logger = "lib.nvim.logger",

  -- LAZY/MEMO (eager - used internally)
  lazy = "lib.lua.lazy",
  memo = "lib.lua.memo",

  -- Table
  array = "lib.lua.tables.array",
  core = "lib.lua.tables.core",
  dict = "lib.lua.tables.dict",
  set = "lib.lua.tables.set",
  functional = "lib.lua.tables.functional",
  safe = "lib.lua.tables.safe",
  unique_table = "lib.lua.tables.unique_table",
  with = "lib.lua.tables.with",

  -- TIM ,
  time_diff = "lib.lua.time.diff",

  -- NORMALIZE
  normalize = "lib.nvim.normalize",

  -- SYSTEM (env snapshot + rpc pipe + system info)
  system = "lib.nvim.system",
  system_info = "lib.nvim.system.info",

  -- TERMINAL
  terminal_escape = "lib.nvim.terminal",
  is_terminal_buf = "lib.nvim.terminal",
  delete_terminal_buf = "lib.nvim.terminal",

  -- HEX
  hex_to_string = "lib.lua.strings.convert.hex_to_string",
}

-- Special handlers for modules with multiple exports
local SPECIAL_HANDLERS = {


  -- lib.nvim
  has_exec = { mod = "lib.nvim.core", key = "has_exec" },

  -- lib.nvim.cross.run exports multiple functions
  shell = { mod = "lib.nvim.cross.run", key = "shell" },
  run = { mod = "lib.nvim.cross.run", key = "run" },
  run_blocking = { mod = "lib.nvim.cross.run", key = "run_blocking" },

  -- functions
  noop = { mod = "lib.lua.functions.meta", kex = "noop" },
  identity = { mod = "lib.lua.functions.meta", kex = "identity" },
  always_true = { mod = "lib.lua.functions.meta", kex = "always_true" },
  always_false = { mod = "lib.lua.functions.meta", kex = "always_false" },
  const = { mod = "lib.lua.functions.meta", kex = "const" },
  raise = { mod = "lib.lua.functions.meta", kex = "raise" },

  -- lib.nvim.fs.path exports multiple functions
  joinpath = { mod = "lib.nvim.fs.path", key = "joinpath" },
  ensure_dir = { mod = "lib.nvim.fs.path", key = "ensure_dir" },

  -- lib.lua.functions.meta exports multiple functions. These were present in
  -- the eager and lazy strategies but not here, so under the *default*
  -- strategy `lib.identity` raised "unknown key" while the Lib class happily
  -- advertised it.
  noop = { mod = "lib.lua.functions.meta", key = "noop" },
  identity = { mod = "lib.lua.functions.meta", key = "identity" },
  always_true = { mod = "lib.lua.functions.meta", key = "always_true" },
  always_false = { mod = "lib.lua.functions.meta", key = "always_false" },
  const = { mod = "lib.lua.functions.meta", key = "const" },
  raise = { mod = "lib.lua.functions.meta", key = "raise" },

  -- lib.nvim.require exports multiple functions
  require_safe = { mod = "lib.nvim.require", key = "safe" },
  require_dir = { mod = "lib.nvim.require", key = "dir" },
  require_lazy = { mod = "lib.nvim.require", key = "lazy" },

  -- lib.nvim.terminal exports multiple functions
  terminal_escape = { mod = "lib.nvim.terminal", key = "escape" },
  is_terminal_buf = { mod = "lib.nvim.terminal", key = "is_terminal_buf" },
  delete_terminal_buf = { mod = "lib.nvim.terminal", key = "delete_terminal_buf" },

  -- lib.lua.strings is special - we want to expose both the module and individual functions
  strings = { mod = "lib.lua.strings", whole = true },
  trim = { mod = "lib.lua.strings", key = "trim" },
  slugify = { mod = "lib.lua.strings", key = "slugify" },
  kebab_case = { mod = "lib.lua.strings", key = "kebab_case" },
  starts_with = { mod = "lib.lua.strings", key = "starts_with" },
  ends_with = { mod = "lib.lua.strings", key = "ends_with" },
  contains = { mod = "lib.lua.strings", key = "contains" },
  split = { mod = "lib.lua.strings", key = "split" },
  join = { mod = "lib.lua.strings", key = "join" },
  replace_all = { mod = "lib.lua.strings", key = "replace_all" },
  capitalize = { mod = "lib.lua.strings", key = "capitalize" },
  uncapitalize = { mod = "lib.lua.strings", key = "uncapitalize" },
  snake_case = { mod = "lib.lua.strings", key = "snake_case" },
  camel_case = { mod = "lib.lua.strings", key = "camel_case" },
  pad_start = { mod = "lib.lua.strings", key = "pad_start" },
  pad_end = { mod = "lib.lua.strings", key = "pad_end" },
  pad_center = { mod = "lib.lua.strings", key = "pad_center" },
  indent = { mod = "lib.lua.strings", key = "indent" },
  dedent = { mod = "lib.lua.strings", key = "dedent" },
  is_empty_or_space = { mod = "lib.lua.strings", key = "is_empty_or_space" },
  remove_prefix = { mod = "lib.lua.strings", key = "remove_prefix" },
  uri_decode = { mod = "lib.lua.strings", key = "uri_decode" },
  normalize_anchor = { mod = "lib.lua.strings", key = "normalize_anchor" },
  has_scheme = { mod = "lib.lua.strings", key = "has_scheme" },
  is_web_url = { mod = "lib.lua.strings", key = "is_web_url" },
  url_under_cursor = { mod = "lib.lua.strings", key = "url_under_cursor" },
  escape_lua_magic = { mod = "lib.lua.strings", key = "escape_lua_magic" },
  find_plain = { mod = "lib.lua.strings", key = "find_plain" },
  replace_plain = { mod = "lib.lua.strings", key = "replace_plain" },
  surround = { mod = "lib.lua.strings", key = "surround" },
  count_lines = { mod = "lib.lua.strings", key = "count_lines" },

  -- json decode
  json_decode_to_string_array = { mod = "lib.lua.json.decode.to_string_array", key = "ensure_string_array" },

  -- json encode (pure Lua)
  json_encode = { mod = "lib.lua.json.encode", key = "encode" },
}

-- ============================================================================
-- Module Cache
-- ============================================================================

local loaded = {}

-- ============================================================================
-- Metatable-based Lazy Loading
-- ============================================================================

setmetatable(LIB, {
  __index = function(_, key)
    -- Check if already loaded
    if loaded[key] then
      return loaded[key]
    end

    -- Check special handlers first
    local handler = SPECIAL_HANDLERS[key]
    if handler then
      local mod = require(handler.mod)
      if handler.whole then
        loaded[key] = mod
        return mod
      elseif handler.key then
        local value = mod[handler.key]
        loaded[key] = value
        return value
      end
    end

    -- Check module map
    local mod_path = MODULE_MAP[key]
    if mod_path then
      local mod = require(mod_path)
      loaded[key] = mod
      return mod
    end

    -- Not found
    error(string.format("lib: unknown key '%s'", key))
  end,
})

---@type Lib
return LIB
