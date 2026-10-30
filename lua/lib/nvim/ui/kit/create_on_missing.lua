---@module 'lib.nvim.ui.kit.create_on_missing'
--- "This path does not exist" dialog for any plugin that opens files (gopath.nvim's `gf`, a path
--- pasted into images.nvim, ...): a `kit.confirm` with the buttons Create / Open in filetree /
--- Cancel.
---
---   - Create: `lib.nvim.fs.create_entry` makes the file (or, for a path ending in a separator, the
---     directory) together with every missing parent directory, then the file is opened (`open`).
---   - Open in filetree: filetree.nvim reveals the deepest directory of the path that does exist.
---     filetree.nvim is optional: the button is there only when it is loaded and set up (read from
---     `package.loaded`, never `require`d: a lazy-loaded tree is not pulled in by a question), or
---     when the caller passes its own `filetree` function.
---   - Cancel (also <Esc>/q, or the dialog closed any other way): nothing happens.
---
--- Every way the dialog ends calls `on_done` exactly once with a result table (see
--- `Lib.UI.Kit.CreateOnMissingResult`). A path that exists already asks nothing: it is opened (a
--- file) and reported as `"exists"`. The question goes through `kit.confirm`, so a dialog hook
--- (`kit.set_dialog_hook`) answers it in a test, by label or by button index.

local confirm = require("lib.nvim.ui.kit.confirm")
local create_entry = require("lib.nvim.fs.create_entry")
local is_dir = require("lib.nvim.fs.is_dir")
local notify = require("lib.nvim.notify").create("[lib.nvim.ui.kit]")

local M = {}

--- Button labels, in the order they are shown.
M.CREATE = "Create"
M.FILETREE = "Open in filetree"
M.CANCEL = "Cancel"

---@internal
--- The deepest existing directory above `abs` (normalized, forward slashes) and the part of `abs`
--- below it. Stops at the root, so a path on a missing drive comes back with the root itself.
---@param abs string
---@return string ancestor
---@return string rest  # never empty for a path that does not exist
local function split_at_existing(abs)
  local cur = abs
  while true do
    local parent = vim.fs.dirname(cur)
    if parent == nil or parent == cur then
      break
    end
    cur = parent
    if is_dir(cur) then
      break
    end
  end
  local skip = cur:sub(-1) == "/" and 1 or 2
  return cur, abs:sub(#cur + skip)
end

---@internal
--- A reveal function for filetree.nvim when it is loaded, set up and its adapter can reveal; nil
--- otherwise. Reads `package.loaded` only: asking a question must not load a lazy plugin.
---@return (fun(path: string): boolean)|nil
local function filetree_reveal()
  local ft = package.loaded["filetree"]
  if type(ft) ~= "table" or type(ft.adapter) ~= "function" then
    return nil
  end
  if type(ft.is_initialized) == "function" and not ft.is_initialized() then
    return nil
  end
  local ok, adapter = pcall(ft.adapter)
  if not ok or type(adapter) ~= "table" or type(adapter.open_reveal) ~= "function" then
    return nil
  end
  return function(path)
    return adapter.open_reveal(path, 0) == true
  end
end

---@internal
--- The reveal function `opts.filetree` asks for: false none, a function itself, nil/true the
--- installed filetree.nvim (if any).
---@param opt boolean|fun(path: string): boolean|nil
---@return (fun(path: string): boolean)|nil
local function resolve_reveal(opt)
  if opt == false then
    return nil
  end
  if type(opt) == "function" then
    return opt
  end
  return filetree_reveal()
end

--- Whether the "Open in filetree" button would be offered with `opts.filetree` left at its
--- default: filetree.nvim is loaded, set up, and its adapter can reveal a path.
---@return boolean
function M.filetree_available()
  return filetree_reveal() ~= nil
end

---@internal
--- Open `path` the way `opts.open` asks. Returns an error message when opening failed.
---@param open boolean|fun(path: string, kind: "file"|"directory")|nil
---@param path string
---@param kind "file"|"directory"
---@return string|nil err
local function open_path(open, path, kind)
  if open == false then
    return nil
  end
  local ok, err
  if type(open) == "function" then
    ok, err = pcall(open, path, kind)
  elseif kind == "file" then
    ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
  else
    return nil
  end
  if not ok then
    return tostring(err)
  end
  return nil
end

--- Ask what to do about a path that does not exist; see the module doc.
---@param opts Lib.UI.Kit.CreateOnMissingOpts
---@return Lib.UI.Kit.Surface|nil  # the dialog (nil when nothing was asked: the path exists)
function M.open(opts)
  if type(opts) ~= "table" or type(opts.path) ~= "string" or opts.path == "" then
    error("kit.create_on_missing: opts.path must be a non-empty string", 2)
  end
  local on_done = opts.on_done or function() end
  local want_dir = opts.path:match("[/\\]$") ~= nil
  local abs = vim.fs.normalize(vim.fn.fnamemodify(opts.path, ":p"))

  local stat = vim.uv.fs_stat(abs)
  if stat then
    local kind = stat.type == "directory" and "directory" or "file"
    local err = open_path(opts.open, abs, kind)
    on_done({ action = "exists", path = abs, kind = kind, err = err })
    return nil
  end

  local ancestor, rest = split_at_existing(abs)
  local reveal = resolve_reveal(opts.filetree)
  local choices = { M.CREATE }
  if reveal then
    choices[#choices + 1] = M.FILETREE
  end
  choices[#choices + 1] = M.CANCEL

  local shown = vim.fn.fnamemodify(abs, ":~:.") .. (want_dir and "/" or "")
  local lines = { shown .. " does not exist." }
  local missing_dir = vim.fs.dirname(rest)
  if want_dir then
    missing_dir = rest
  end
  if missing_dir and missing_dir ~= "." and missing_dir ~= "" then
    lines[#lines + 1] = "Missing directories are created too: " .. missing_dir .. "/"
  end

  return confirm.open({
    question = table.concat(lines, "\n"),
    title = opts.title or (want_dir and "Create directory?" or "Create file?"),
    theme = opts.theme,
    choices = choices,
    default = 1,
    on_answer = function(choice)
      if choice == M.CREATE then
        local ok, kind, path_or_err = create_entry(ancestor, rest .. (want_dir and "/" or ""))
        if not ok then
          notify.error(("could not create %s: %s"):format(shown, tostring(path_or_err)))
          on_done({ action = "error", path = abs, err = path_or_err })
          return
        end
        ---@cast kind "file"|"directory"
        ---@cast path_or_err string
        local created = vim.fs.normalize(path_or_err)
        local err = open_path(opts.open, created, kind)
        if err then
          notify.error(("created %s, but could not open it: %s"):format(shown, err))
        end
        on_done({ action = "created", path = created, kind = kind, err = err })
      elseif choice == M.FILETREE and reveal then
        local ok, res = pcall(reveal, ancestor)
        if not ok or res == false then
          local err = ok and "the file tree could not reveal it" or tostring(res)
          notify.error(("could not open %s in the file tree: %s"):format(ancestor, err))
          on_done({ action = "error", path = ancestor, err = err })
          return
        end
        on_done({ action = "filetree", path = ancestor })
      else
        on_done({ action = "cancelled", path = abs })
      end
    end,
  })
end

return M
