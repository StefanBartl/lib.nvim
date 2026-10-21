---@module 'lib.nvim.fs.latest_file'
--- The newest file of some folders, optionally only an image and only a recent one.
---@description
--- For "attach the screenshot I just took": look into the folders, take the file
--- with the latest modification time, and refuse to guess when it is older than
--- `max_age_s` -- the caller then asks instead of attaching last week's picture.

local M = {}

local IMAGE_EXTS = { "png", "jpg", "jpeg", "gif", "webp", "bmp" }

---@class Lib.LatestFile.Opts
---@field exts? string[]     Allowed extensions, lower case, no dot (default: common image types)
---@field max_age_s? number  Reject a file older than this many seconds (default: no limit)
---@field now? number        Current time in seconds (for specs; default: now)

---@class Lib.LatestFile.Found
---@field path string   Forward-slash path of the file
---@field age_s number  Seconds since its last modification
---@field mtime number  Modification time in seconds

---@param dirs string[]
---@param opts? Lib.LatestFile.Opts
---@return Lib.LatestFile.Found|nil newest  The newest matching file (also when too old, see `err`)
local function newest_in(dirs, opts)
  local want = {}
  for _, e in ipairs((opts and opts.exts) or IMAGE_EXTS) do
    want[e:lower()] = true
  end
  local now = (opts and opts.now) or os.time()
  local best
  for _, dir in ipairs(dirs) do
    local norm = vim.fs.normalize(dir)
    local handle = vim.uv.fs_scandir(norm)
    while handle do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local ext = name:match("%.([%w]+)$")
      if kind ~= "directory" and ext and want[ext:lower()] then
        local full = norm:gsub("/+$", "") .. "/" .. name
        local st = vim.uv.fs_stat(full)
        if st and st.type == "file" then
          local mtime = st.mtime.sec + (st.mtime.nsec or 0) / 1e9
          if not best or mtime > best.mtime then
            best = { path = full, mtime = mtime, age_s = math.max(0, now - mtime) }
          end
        end
      end
    end
  end
  return best
end

---Find the newest matching file in `dirs`.
---@param dirs string[]
---@param opts? Lib.LatestFile.Opts
---@return Lib.LatestFile.Found|nil found   Set when a file qualifies
---@return string|nil err                   Why none does ("no file in ..." or "newest file is N s old")
---@return Lib.LatestFile.Found|nil too_old The newest file when it exists but is too old
function M.find(dirs, opts)
  if type(dirs) ~= "table" or #dirs == 0 then
    return nil, "no folder given"
  end
  local best = newest_in(dirs, opts)
  if not best then
    return nil, "no matching file in " .. table.concat(dirs, ", ")
  end
  local max_age = opts and opts.max_age_s
  if max_age and best.age_s > max_age then
    return nil,
      ("the newest file (%s) is %d s old, more than %d s"):format(
        best.path,
        math.floor(best.age_s),
        math.floor(max_age)
      ),
      best
  end
  return best, nil, nil
end

return M
