---@module 'lib.nvim.fs.portable'
--- Make a text artifact portable between machines: host-specific root paths become placeholders when it is
--- written, and the placeholders are resolved again when it is read -- through a temporary copy, so the stored
--- file is never touched and stays valid for every machine that shares it.
---
--- Generalised from `sessions.nvim`'s `portable.lua` (a `:mksession` file pins itself to the machine's
--- paths); useful for any plugin that syncs notes, bookmarks or project configs across machines.
---
--- A root is a `{ path = "/home/me/proj", placeholder = "{{PROJECT_ROOT}}" }` pair. Replacement is
--- boundary-aware: `E:/repos/ui.nvim` is a prefix of `E:/repos/ui.nvim-backup`, and the latter's paths must
--- not become `{{ROOT}}-backup/...`.
---
--- ```lua
--- local portable = require("lib.nvim.fs.portable")
--- local roots = { { path = vim.fn.getcwd(), placeholder = "{{PROJECT_ROOT}}" } }
---
--- portable.make_file(session_file, roots)            -- after saving: paths -> placeholders, in place
---
--- local src, is_temp = portable.resolve_file(session_file, roots)
--- vim.cmd.source(src)                                -- placeholders -> this machine's paths
--- if is_temp then vim.fn.delete(src) end
--- ```

local M = {}

---@class Lib.Fs.Portable.Root
---@field path string          Absolute path of the root on THIS machine.
---@field placeholder string   Text that stands for it in the stored artifact.

---@class Lib.Fs.Portable.Opts
---@field remap? table<string, string>  Prefixes of another machine (`{ ["C:/Users/a"] = "/home/a" }`) to translate on resolve.
---@field suffix? string                Suffix of the temporary copy (default ".tmp").

---@internal
--- A path ends where the next byte cannot continue a file name.
---@param c string
---@return boolean
local function continues_name(c)
  return c ~= "" and c:match("[%w_%-%.~]") ~= nil
end

---@internal
--- A path starts where the previous byte cannot belong to a longer path: not a name character and not a
--- separator (`/srv/home/me` must not match the root `/home/me`).
--- Exception: a root right behind a URL scheme (`oil:///home/me`, `file:///C:/x`, `term://~/x`) starts there.
---@param before string  The text in front of the hit (a window of it is enough).
---@return boolean
local function continues_path(before)
  local c = before:sub(-1)
  if c == "" or c:match("[%w_%-%.~/\\]") == nil then
    return false
  end
  return before:find("%a[%w+.%-]*://+$") == nil
end

---@internal
--- Replace every occurrence of `needle` that starts and ends at a path boundary. Plain text on both sides.
---@param content string
---@param needle string
---@param replacement string
---@return string
local function boundary_replace(content, needle, replacement)
  if needle == "" then
    return content
  end
  local out, pos = {}, 1
  while true do
    local s, e = content:find(needle, pos, true)
    if not s then
      out[#out + 1] = content:sub(pos)
      break
    end
    if
      continues_name(content:sub(e + 1, e + 1))
      or continues_path(content:sub(math.max(1, s - 40), s - 1))
    then
      -- Not a boundary: keep the text and resume right after the first byte of this hit.
      out[#out + 1] = content:sub(pos, s)
      pos = s + 1
    else
      out[#out + 1] = content:sub(pos, s - 1)
      out[#out + 1] = replacement
      pos = e + 1
    end
  end
  return table.concat(out)
end

---@internal
--- `/`-separated form of `path` without a trailing slash (a root `C:/` keeps its slash).
---@param path string
---@return string
local function slashed(path)
  local p = path:gsub("\\", "/")
  if #p > 1 and p:sub(-1) == "/" and not p:match("^%a:/$") then
    p = p:gsub("/+$", "")
  end
  return p
end

---@internal
--- The spellings a tool may have written for `path`: forward-slashed absolute, backslashed, the `:~` form.
---@param path string
---@return string[]
local function spellings(path)
  local abs = slashed(path)
  local out = { abs }
  -- (the drive letter in the other case: Windows paths compare case-insensitively)
  local drive = abs:match("^(%a):")
  if drive then
    local flipped = (drive:lower() == drive and drive:upper() or drive:lower()) .. abs:sub(2)
    out[#out + 1] = flipped
  end
  -- (a native Windows spelling, as a tool that does not normalise separators writes it)
  local back = abs:gsub("/", "\\")
  if back ~= abs then
    out[#out + 1] = back
  end
  if vim and vim.fn and vim.fn.fnamemodify then
    local ok, tilde = pcall(vim.fn.fnamemodify, path, ":~")
    if ok and type(tilde) == "string" then
      tilde = slashed(tilde)
      if tilde ~= abs and tilde ~= "" then
        out[#out + 1] = tilde
      end
    end
  end
  return out
end

---@internal
---@param roots Lib.Fs.Portable.Root[]
---@return Lib.Fs.Portable.Root[]
local function checked(roots)
  if type(roots) ~= "table" then
    error("lib.nvim.fs.portable: roots must be a list of { path, placeholder }", 3)
  end
  local list = {}
  for i, root in ipairs(roots) do
    if
      type(root) ~= "table"
      or type(root.path) ~= "string"
      or root.path == ""
      or type(root.placeholder) ~= "string"
      or root.placeholder == ""
    then
      error(("lib.nvim.fs.portable: roots[%d] needs a path and a placeholder"):format(i), 3)
    end
    list[#list + 1] = root
  end
  return list
end

---Replace the roots in `content` by their placeholders. The longest root wins where roots are nested.
---@param content string
---@param roots Lib.Fs.Portable.Root[]
---@return string
function M.make(content, roots)
  local list = checked(roots)
  -- Longest spelling first, so a nested root is not swallowed by its parent.
  local jobs = {}
  for _, root in ipairs(list) do
    for _, needle in ipairs(spellings(root.path)) do
      jobs[#jobs + 1] = { needle = needle, placeholder = root.placeholder }
    end
  end
  table.sort(jobs, function(a, b)
    return #a.needle > #b.needle
  end)
  for _, job in ipairs(jobs) do
    content = boundary_replace(content, job.needle, job.placeholder)
  end
  return content
end

---Replace the placeholders in `content` by this machine's paths (forward-slashed), then translate
---`opts.remap` prefixes. Placeholders that are not in `roots` stay as they are.
---@param content string
---@param roots Lib.Fs.Portable.Root[]
---@param opts? Lib.Fs.Portable.Opts
---@return string
function M.resolve(content, roots, opts)
  local list = checked(roots)
  for _, root in ipairs(list) do
    -- (a placeholder is plain text: no boundary rule, it is delimited by its own braces or name)
    local path = slashed(root.path)
    local out, pos = {}, 1
    while true do
      local s, e = content:find(root.placeholder, pos, true)
      if not s then
        out[#out + 1] = content:sub(pos)
        break
      end
      out[#out + 1] = content:sub(pos, s - 1)
      out[#out + 1] = path
      pos = e + 1
      -- a root that is a bare drive or "/" already ends in a slash
      if path:sub(-1) == "/" and content:sub(pos, pos) == "/" then
        pos = pos + 1
      end
    end
    content = table.concat(out)
  end
  for old_root, new_root in pairs((opts and opts.remap) or {}) do
    if type(old_root) == "string" and type(new_root) == "string" then
      content = boundary_replace(content, old_root, new_root)
    end
  end
  return content
end

---Rewrite `path` in place with the roots replaced by placeholders (byte-exact, atomic).
---@param path string
---@param roots Lib.Fs.Portable.Root[]
---@return boolean ok
---@return string|nil err
function M.make_file(path, roots)
  local content, err = require("lib.nvim.fs.read")(path)
  if not content then
    return false, err
  end
  local made = M.make(content, roots)
  if made == content then
    return true, nil
  end
  return require("lib.nvim.fs.write.atomic")(path, made)
end

---Source of `path` with the placeholders resolved for this machine. The stored file is never changed: when
---anything had to be resolved the result is a temporary copy, otherwise `path` itself.
---@param path string
---@param roots Lib.Fs.Portable.Root[]
---@param opts? Lib.Fs.Portable.Opts
---@return string source   `path`, or the temporary copy.
---@return boolean is_temp The caller deletes `source` (`vim.fn.delete`) when it is done with it.
---@return string|nil err  Set when reading or writing failed and `path` is returned unresolved.
function M.resolve_file(path, roots, opts)
  local content, err = require("lib.nvim.fs.read")(path)
  if not content then
    return path, false, err
  end
  local resolved = M.resolve(content, roots, opts)
  if resolved == content then
    return path, false, nil
  end
  local tmp = vim.fn.tempname() .. ((opts and opts.suffix) or ".tmp")
  local ok, werr = require("lib.nvim.fs.write.atomic")(tmp, resolved)
  if not ok then
    -- never hand out a path that does not exist: fall back to the stored file
    return path, false, werr
  end
  return tmp, true, nil
end

return M
