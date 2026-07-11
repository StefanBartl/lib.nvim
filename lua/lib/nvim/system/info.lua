---@module 'lib.nvim.system.info'
--- Cross-platform system information (OS, CPU, RAM, GPU, uptime, ...).
---
--- Library-side home of the per-config `:SystemInfo` user command. Prefers
--- `fastfetch`/`neofetch` when installed; otherwise falls back to a small
--- platform-native probe (PowerShell/CIM on Windows, `sw_vers`/`sysctl` on
--- macOS, `/proc` & DMI on Linux and WSL). Commands are built as argv lists,
--- never shell strings, so the classic quoting problems (^M leftovers, empty
--- fields from broken escapes) cannot occur — Neovim runs list commands
--- directly, without involving 'shell'/cmd.exe.
---
---   local info = require("lib.nvim.system.info")
---   local lines = info.get()   -- string[]|nil: "OS : ...", "CPU : ...", ...
---   info.show()                -- floating window + clipboard copy
---   info.create_usercmd()      -- registers :SystemInfo
---
--- Pure by default: `build_cmd`/`get` only probe; the float, the clipboard
--- write and the user command are opt-in via `show`/`create_usercmd`.

require("lib.nvim.system.@types")

local notify = require("lib.nvim.notify").create("[lib.nvim.system.info]")

local M = {}

--- Windows probe: CIM queries, no external tools required.
local WINDOWS_SCRIPT = [[
$ErrorActionPreference = 'SilentlyContinue'
$os    = Get-CimInstance Win32_OperatingSystem
$cs    = Get-CimInstance Win32_ComputerSystem
$cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu   = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ', '
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$uptime = (Get-Date) - $os.LastBootUpTime

Write-Output "OS           : $($os.Caption)"
Write-Output "Version      : $($os.Version)"
Write-Output "Architecture : $($os.OSArchitecture)"
Write-Output "Hostname     : $($cs.Name)"
Write-Output "Manufacturer : $($cs.Manufacturer)"
Write-Output "Model        : $($cs.Model)"
Write-Output "CPU          : $($cpu.Name.Trim())"
Write-Output "RAM          : $ramGB GB"
Write-Output "GPU          : $gpu"
Write-Output "User         : $env:USERNAME"
Write-Output "Uptime       : $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
]]

--- macOS probe: sw_vers / sysctl / system_profiler.
local MACOS_SCRIPT = [[
echo "OS           : $(sw_vers -productName) $(sw_vers -productVersion)"
echo "Build        : $(sw_vers -buildVersion)"
echo "Architecture : $(uname -m)"
echo "Hostname     : $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "Model        : $(sysctl -n hw.model)"
echo "CPU          : $(sysctl -n machdep.cpu.brand_string)"
echo "RAM          : $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
echo "GPU          : $(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2; exit}')"
echo "User         : $(whoami)"
echo "Uptime       : $(uptime | sed 's/.*up //;s/,.*load.*//')"
]]

--- Linux/WSL probe: /etc/os-release, /proc, DMI. Every field degrades to
--- "unknown"/empty instead of failing when a source is unavailable.
local LINUX_SCRIPT = [[
echo "OS           : $( . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME" )"
echo "Kernel       : $(uname -r)"
echo "Architecture : $(uname -m)"
echo "Hostname     : $(hostname)"
echo "Manufacturer : $(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
echo "Model        : $(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)"
echo "CPU          : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
echo "RAM          : $(free -h --si 2>/dev/null | awk '/Mem:/{print $2}')"
echo "GPU          : $(lspci 2>/dev/null | grep -Ei 'vga|3d controller' | cut -d: -f3 | sed 's/^ //' | paste -sd ', ')"
echo "User         : $(whoami)"
echo "Uptime       : $(uptime -p 2>/dev/null)"
]]

--- Build the probe command as an argv list.
--- Order: fastfetch > neofetch > platform-native fallback. The fetch tools are
--- skipped with `prefer_fetch = false` (uniform "Key : Value" output instead).
---@param opts? Lib.System.Info.BuildCmdOpts
---@return string[] argv
function M.build_cmd(opts)
  local prefer_fetch = not opts or opts.prefer_fetch ~= false

  if prefer_fetch then
    if vim.fn.executable("fastfetch") == 1 then
      return { "fastfetch", "--logo", "none" }
    elseif vim.fn.executable("neofetch") == 1 then
      return { "neofetch", "--off" }
    end
  end

  if require("lib.nvim.cross.platform.is_windows")() then
    local ps_exe = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
    return { ps_exe, "-NoProfile", "-NonInteractive", "-Command", WINDOWS_SCRIPT }
  elseif require("lib.nvim.cross.platform.is_macos")() then
    return { "/bin/bash", "-c", MACOS_SCRIPT }
  else
    -- Linux and WSL share the same probe; WSL reports the distro, which is
    -- the correct answer for the environment Neovim actually runs in.
    local sh = vim.fn.executable("bash") == 1 and "bash" or "sh"
    return { sh, "-c", LINUX_SCRIPT }
  end
end

--- Run the probe and return the cleaned output lines (no CRLF remnants, no
--- blank lines). Returns `nil, err` when the probe fails or yields nothing.
---@param opts? Lib.System.Info.BuildCmdOpts
---@return string[]|nil lines
---@return string|nil err
function M.get(opts)
  local ok, data = pcall(vim.fn.systemlist, M.build_cmd(opts))
  if not ok then
    return nil, tostring(data)
  end

  local lines = {}
  for _, line in ipairs(data) do
    line = line:gsub("\r$", "")
    if line:match("%S") then
      lines[#lines + 1] = line
    end
  end

  if #lines == 0 then
    return nil, "system probe produced no output"
  end
  return lines, nil
end

--- Copy `text` to the system clipboard ("+ register plus platform fallbacks,
--- and the "* selection register where it exists).
---@param text string
---@return boolean ok
local function to_clipboard(text)
  local ok = require("lib.nvim.cross.copy_to_clipboard")(text)
  pcall(vim.fn.setreg, "*", text)
  return ok
end

--- Gather system information, show it in a centered floating window and
--- (by default) copy it to the clipboard. `q`/`<Esc>` close the float.
---@param opts? Lib.System.Info.ShowOpts
---@return integer|nil winid
---@return integer|nil bufnr
function M.show(opts)
  opts = opts or {}

  local lines, err = M.get(opts)
  if not lines then
    notify.error("system info probe failed: " .. tostring(err))
    return nil, nil
  end

  if opts.clipboard ~= false then
    if to_clipboard(table.concat(lines, "\n")) then
      notify.info("System info copied to clipboard")
    end
  end

  local make_scratch = require("lib.nvim.window.make_scratch")
  return make_scratch({
    lines = lines,
    title = opts.title or " System Information ",
    title_pos = "center",
    nice_quit = true,
    width = math.min(60, math.max(1, vim.o.columns - 10)),
  })
end

--- Register the user command (default `:SystemInfo`) that opens the float.
---@param name? string # Command name, defaults to "SystemInfo".
---@param opts? Lib.System.Info.ShowOpts # Forwarded to `show` on execution.
function M.create_usercmd(name, opts)
  require("lib.nvim.usercmd").create(name or "SystemInfo", function()
    M.show(opts)
  end, { desc = "Show system information (float + clipboard)" })
end

---@type Lib.System.Info
return M
