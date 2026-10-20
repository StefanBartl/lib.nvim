---@module 'lib.nvim.cross.copy_image_to_clipboard'
--- Put a PNG file on the system clipboard as an IMAGE, not as its path or bytes as text.
---
--- `lib.nvim.cross.copy_to_clipboard` is text-only, and Neovim's `+` register has no notion of
--- an image at all, so this always goes to an OS tool:
---
--- - native Windows: PowerShell `-STA` with `System.Windows.Forms.Clipboard::SetImage`
---   (`powershell.exe`, else `pwsh`);
--- - WSL: the same through `powershell.exe`, the path translated by `WSLENV`'s `/p` flag;
--- - Linux: `wl-copy --type image/png` under Wayland, `xclip -t image/png` under X11, then
---   whichever of the two is on PATH;
--- - macOS: `osascript` reading the file `as «class PNGf»`.
---
--- **The path never enters a command string.** Both scripts are constant; the path reaches
--- PowerShell and AppleScript through the `LIB_NVIM_CLIP_IMAGE` environment variable (the route
--- `lib.nvim.cross.powershell` recommends), `xclip` as a plain argv element and `wl-copy` on
--- stdin. A file name with quotes, `$`, `;` or typographic quotes is therefore just a file name
--- -- the same stance that fixed command injection in the text variant.
---
--- PNG only, checked by the file's signature rather than its extension: macOS needs to be told
--- the type, Linux announces it as `image/png`, and a crop written by `images.convert` is a PNG.
---
--- ```lua
--- require("lib.nvim.cross.copy_image_to_clipboard")("/tmp/crop.png", function(ok, err)
---   if not ok then vim.notify(err, vim.log.levels.WARN) end
--- end)
--- ```

local M = {}

---@type string Environment variable that carries the path to PowerShell / AppleScript.
local ENV_KEY = "LIB_NVIM_CLIP_IMAGE"

---@type string The PNG signature, the first eight bytes of every PNG file.
local PNG_SIGNATURE = string.char(137, 80, 78, 71, 13, 10, 26, 10)

-- Constant script text: the path is read from the environment, never spliced in. `-STA` is
-- required by the WinForms clipboard; `Dispose` releases the file, the clipboard keeps a copy.
local WINDOWS_SCRIPT = table.concat({
  "$ErrorActionPreference = 'Stop'",
  "Add-Type -AssemblyName System.Windows.Forms, System.Drawing",
  "$img = [System.Drawing.Image]::FromFile($env:" .. ENV_KEY .. ")",
  "try { [System.Windows.Forms.Clipboard]::SetImage($img) } finally { $img.Dispose() }",
}, "; ")

local MACOS_SCRIPT = 'set the clipboard to (read (POSIX file (system attribute "'
  .. ENV_KEY
  .. '")) as «class PNGf»)'

---@class Lib.Cross.ImageClipboard.Platform
---@field windows boolean native Windows (not WSL)
---@field wsl boolean
---@field macos boolean
---@field linux boolean Linux outside WSL
---@field wayland boolean `$WAYLAND_DISPLAY` is set
---@field x11 boolean `$DISPLAY` is set
---@field wslenv? string the current `$WSLENV`
---@field has fun(bin: string): boolean whether `bin` is on PATH

---@class Lib.Cross.ImageClipboard.Plan
---@field argv string[] the process to run
---@field env? table<string, string> extra environment for it (merged with the current one)
---@field stdin_file? boolean feed the file's bytes on stdin
---@field forks? boolean the tool leaves a background child owning the selection: no stdout/stderr pipes

---@param bins string[]
---@param has fun(bin: string): boolean
---@return string|nil
local function first_available(bins, has)
  for _, bin in ipairs(bins) do
    if has(bin) then
      return bin
    end
  end
  return nil
end

---@param bin string
---@param abs string
---@return Lib.Cross.ImageClipboard.Plan
local function linux_plan(bin, abs)
  -- Both tools fork a child that keeps serving the selection, and that child inherits
  -- stdout/stderr. `vim.system` reports the exit only once those pipes reach EOF, so with
  -- pipes `on_done` would wait until some other program takes the clipboard. Neovim's own
  -- clipboard provider works around the same thing ("xclip does not close stdout").
  if bin == "wl-copy" then
    return { argv = { "wl-copy", "--type", "image/png" }, stdin_file = true, forks = true }
  end
  return {
    argv = { "xclip", "-selection", "clipboard", "-t", "image/png", "-i", abs },
    forks = true,
  }
end

--- How to copy the PNG at `abs` on `platform`. Pure: runs nothing, reads no file, so every
--- platform's choice can be checked from any other one.
---@param abs string absolute path of the PNG
---@param platform Lib.Cross.ImageClipboard.Platform
---@return Lib.Cross.ImageClipboard.Plan|nil plan
---@return string|nil err why nothing can copy it here
function M.plan(abs, platform)
  local has = platform.has

  if platform.windows then
    local ps = first_available({ "powershell.exe", "pwsh" }, has)
    if not ps then
      return nil, "neither powershell.exe nor pwsh is on PATH"
    end
    return {
      argv = { ps, "-NoProfile", "-NonInteractive", "-STA", "-Command", WINDOWS_SCRIPT },
      env = { [ENV_KEY] = abs },
    }
  end

  if platform.wsl then
    if not has("powershell.exe") then
      return nil, "powershell.exe is not reachable from WSL"
    end
    -- `/p` makes WSL translate the value into a Windows path on the way into powershell.exe.
    local wslenv = platform.wslenv or ""
    local entry = ENV_KEY .. "/p"
    return {
      argv = {
        "powershell.exe",
        "-NoProfile",
        "-NonInteractive",
        "-STA",
        "-Command",
        WINDOWS_SCRIPT,
      },
      env = { [ENV_KEY] = abs, WSLENV = wslenv == "" and entry or (wslenv .. ":" .. entry) },
    }
  end

  if platform.macos then
    if not has("osascript") then
      return nil, "osascript is not on PATH"
    end
    return { argv = { "osascript", "-e", MACOS_SCRIPT }, env = { [ENV_KEY] = abs } }
  end

  if platform.linux then
    local preferred = {}
    if platform.wayland then
      preferred[#preferred + 1] = "wl-copy"
    end
    if platform.x11 then
      preferred[#preferred + 1] = "xclip"
    end
    local bin = first_available(preferred, has) or first_available({ "wl-copy", "xclip" }, has)
    if not bin then
      return nil, "no image-capable clipboard tool: install wl-clipboard (Wayland) or xclip (X11)"
    end
    return linux_plan(bin, abs)
  end

  return nil, "no image clipboard support on this platform"
end

--- The platform as `M.plan` sees it, read from the running Neovim.
---@return Lib.Cross.ImageClipboard.Platform
function M.detect()
  local wsl = require("lib.nvim.cross.platform.is_wsl")()
  local function env(name)
    return vim.uv.os_getenv(name) or ""
  end
  return {
    windows = require("lib.nvim.cross.platform.is_windows")() and not wsl,
    wsl = wsl,
    macos = require("lib.nvim.cross.platform.is_macos")(),
    linux = require("lib.nvim.cross.platform.is_linux")() and not wsl,
    wayland = env("WAYLAND_DISPLAY") ~= "",
    x11 = env("DISPLAY") ~= "",
    wslenv = env("WSLENV"),
    has = require("lib.nvim.core").has_exec,
  }
end

--- The file's bytes when it is a readable PNG.
---@param abs string
---@return string|nil bytes
---@return string|nil err
local function read_png(abs)
  local fd = io.open(abs, "rb")
  if not fd then
    return nil, "cannot read " .. abs
  end
  local bytes = fd:read("*a")
  fd:close()
  if type(bytes) ~= "string" or bytes:sub(1, #PNG_SIGNATURE) ~= PNG_SIGNATURE then
    return nil, "not a PNG file: " .. abs
  end
  return bytes
end

--- The `vim.system` options for `plan`: its environment, the file on stdin when it reads
--- one, and no stdout/stderr pipes for a tool that forks (see `linux_plan`).
---@param plan Lib.Cross.ImageClipboard.Plan
---@param bytes string the file's contents
---@return vim.SystemOpts
function M.system_opts(plan, bytes)
  local opts = { env = plan.env, text = true }
  if plan.stdin_file then
    opts.stdin = bytes
  end
  if plan.forks then
    opts.stdout = false
    opts.stderr = false
  end
  return opts
end

--- Copy the PNG at `path` to the clipboard as an image. Asynchronous; `on_done(ok, err)` runs
--- on the main loop once the tool has finished (or at once, scheduled, when it cannot start).
---@param path string
---@param on_done? fun(ok: boolean, err: string|nil)
---@return nil
function M.copy(path, on_done)
  local function finish(ok, err)
    if on_done then
      vim.schedule(function()
        on_done(ok, err)
      end)
    end
  end

  if type(path) ~= "string" or path == "" then
    return finish(false, "no file given")
  end
  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local bytes, read_err = read_png(abs)
  if not bytes then
    return finish(false, read_err)
  end

  local plan, plan_err = M.plan(abs, M.detect())
  if not plan then
    return finish(false, plan_err)
  end

  local started, err = pcall(vim.system, plan.argv, M.system_opts(plan, bytes), function(obj)
    if obj.code == 0 then
      return finish(true, nil)
    end
    local msg = vim.trim(obj.stderr or "")
    finish(
      false,
      ("%s failed (exit %d)%s"):format(plan.argv[1], obj.code, msg ~= "" and (": " .. msg) or "")
    )
  end)
  if not started then
    finish(false, ("could not start %s: %s"):format(plan.argv[1], tostring(err)))
  end
end

return setmetatable(M, {
  __call = function(_, path, on_done)
    return M.copy(path, on_done)
  end,
})
