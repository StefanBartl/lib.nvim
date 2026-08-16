---@module 'lib.nvim.fs.path.object'
--- OOP `Path` object — a chainable `:exists()`/`:read()`/`:joinpath()`/
--- `:iter()` wrapper, built on `lib.lua.class`, akin to `plenary.Path`.
---
--- Sibling to the flat `lib.nvim.fs.path` (`from_repo_relative`/
--- `joinpath`/`ensure_dir`), which keeps its current API untouched — this
--- is an additive, chainable alternative, not a replacement. Every method
--- here is a thin facade over an existing `lib.nvim.fs` primitive; none of
--- the actual filesystem logic is reimplemented.
---
---```lua
--- local Path = require("lib.nvim.fs.path.object")
---
--- local p = Path.new("/tmp/report.txt")
--- p:write("hello\n")
--- p:exists()        --> true
--- p:is_dir()         --> false
--- p:read()           --> "hello\n"
--- p:parent():read()  --> reading in the parent dir, e.g. after :joinpath()
--- p:joinpath("x")    --> a new Path("/tmp/report.txt/x")
---```

require("lib.nvim.fs.path.@types")

local class = require("lib.lua.class")

local Path = class.new("Path")

---@param path string
function Path:init(path)
  self.path = path
end

---@return boolean
function Path:exists()
  local uv = vim.uv or vim.loop
  return uv.fs_stat(self.path) ~= nil
end

---@return boolean
function Path:is_dir()
  local uv = vim.uv or vim.loop
  local st = uv.fs_stat(self.path)
  return st ~= nil and st.type == "directory"
end

---@return string|nil content
---@return string|nil err
function Path:read()
  return require("lib.nvim.fs.read")(self.path)
end

---@param content string
---@return boolean ok
---@return string|nil err
function Path:write(content)
  return require("lib.nvim.fs.write.to_file")(self.path, content)
end

--- Join `...` onto this path, returning a new `Path`.
---@param ... string
---@return table
function Path:joinpath(...)
  local fs_path = require("lib.nvim.fs.path")
  return Path.new(fs_path.joinpath({ self.path, ... }))
end

--- The parent directory, as a new `Path`.
---@return table
function Path:parent()
  return Path.new(vim.fs.dirname(self.path))
end

--- Recursively collect absolute paths under this path. A full recursive
--- walk, not plenary's shallow `Path:iter()` — the primitive this
--- delegates to (`lib.nvim.fs.collect_recursive`) has no depth limit.
---@param opts? Lib.Fs.CollectRecursive.Opts
---@return string[]
function Path:iter(opts)
  return require("lib.nvim.fs.collect_recursive").collect(self.path, opts)
end

---@type Lib.Fs.Path.ObjectModule
return Path
