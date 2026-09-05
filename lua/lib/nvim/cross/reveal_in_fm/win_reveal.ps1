<#
  win_reveal.ps1 — reveal a path in Windows Explorer AND raise that window.

  Launching `explorer.exe /select,<path>` from Neovim already worked: the
  window is created. What did NOT work is the window coming to the FRONT,
  which is the only part the user can see — so every failure looked like
  "the file manager did not open".

  Why: Windows only lets a process call SetForegroundWindow when it already
  owns the foreground window (or was handed the right by one that did). When
  Neovim runs inside a terminal, the foreground window belongs to the
  terminal host (WindowsTerminal.exe, wezterm.exe, …) — nvim.exe is merely a
  child process and is denied. Explorer, spawned by nvim and likewise without
  foreground rights, therefore creates its window BEHIND everything and at
  most flashes its taskbar button. In a GUI Neovim (Neovide, nvim-qt) nvim.exe
  IS the foreground process, so the very same code appeared to work — which is
  why this bug kept coming back and going away with no visible pattern.

  The fix is the documented AttachThreadInput dance: temporarily attach our
  input queue to both the current foreground thread and the target window's
  thread, which makes Windows treat the SetForegroundWindow call as coming
  from the foreground process, then detach again. This is the same mechanism
  WScript.Shell's AppActivate uses internally, but applied to a window handle
  we located ourselves rather than to a guessed window title.

  Invoked detached by `lib.nvim.cross.reveal_in_fm`; never blocks Neovim.

  Exit codes: 0 = a window was raised, 1 = either Explorer was launched but
  no window could be located within -TimeoutMs (nothing is retried; the
  window, if it appears late, is simply left unraised), or -Path contained a
  literal double quote and was refused before Explorer was ever launched
  (see the check right below -- a WSL-sourced path can carry one, and this
  script has no way to escape it for explorer.exe safely).
#>
[CmdletBinding()]
param(
  # Absolute Windows path (backslashes) of the file or directory to show.
  [Parameter(Mandatory = $true)][string]$Path,

  # Pass /select,<Path> so a FILE is highlighted inside its parent directory.
  # Without it, -Path is treated as the folder to navigate into.
  [switch]$Select,

  # Navigate an already-open Explorer window instead of creating another one.
  [switch]$Reuse,

  # How long to keep looking for the window Explorer was asked to show.
  [int]$TimeoutMs = 6000
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

if ($Path -like '*"*') {
  # A native Windows path can never contain a literal `"` (Win32 rejects it
  # in a filename), but $Path can arrive here already translated from a WSL
  # path via wslpath -w, which does not filter anything -- Linux happily
  # allows `"` in a filename. Left as-is, that quote would close the
  # manually-built -ArgumentList string below early and let the rest of the
  # filename smuggle extra tokens onto explorer.exe's command line.
  # explorer.exe's own quote-escaping convention for a literal quote inside
  # a quoted token is not documented rigorously enough to trust a hand-rolled
  # unescape here, so this fails closed instead of attempting one: the
  # caller (lib.nvim.cross.reveal_in_fm) never reads this process's exit code
  # or output -- it is fire-and-forget by design -- so the visible effect is
  # simply no window raised, the same as any other silent failure this
  # script already exits 1 on below.
  [Console]::Error.WriteLine("win_reveal: refusing a path containing a double quote: $Path")
  exit 1
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class LibNvimReveal {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool   SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool   BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern bool   ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool   IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool   AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern uint   GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

  const int SW_RESTORE = 9;

  // Returns true when the window really ended up in the foreground, so the
  // caller can report an honest exit code instead of assuming success.
  public static bool Raise(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return false;

    IntPtr fg  = GetForegroundWindow();
    uint fgThr = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint tgThr = GetWindowThreadProcessId(hwnd, IntPtr.Zero);
    uint myThr = GetCurrentThreadId();

    // Attaching to the foreground thread is what actually lifts the
    // foreground lock; attaching to the target thread additionally lets
    // BringWindowToTop reorder it. Both are undone below, unconditionally.
    bool aFg = (fgThr != myThr) && AttachThreadInput(myThr, fgThr, true);
    bool aTg = (tgThr != myThr) && (tgThr != fgThr) && AttachThreadInput(myThr, tgThr, true);
    try {
      if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
      BringWindowToTop(hwnd);
      SetForegroundWindow(hwnd);
    } finally {
      if (aTg) AttachThreadInput(myThr, tgThr, false);
      if (aFg) AttachThreadInput(myThr, fgThr, false);
    }

    return GetForegroundWindow() == hwnd;
  }
}
'@

# Trailing separators and case both vary between what Explorer reports and
# what the caller passed, so every comparison goes through this.
function Format-Key([string]$p) {
  if ([string]::IsNullOrEmpty($p)) { return '' }
  return ($p -replace '[\\/]+$', '').ToLowerInvariant()
}

# Shell.Application.Windows() also yields non-folder shell windows; anything
# without a .Document.Folder is not an Explorer folder window and is skipped.
# Every property access is guarded: a window closing mid-enumeration throws.
function Get-ExplorerWindows {
  $result = @()
  $shell = New-Object -ComObject Shell.Application
  if ($null -eq $shell) { return $result }
  try { $windows = @($shell.Windows()) } catch { return $result }
  foreach ($w in $windows) {
    try {
      $folder = $w.Document.Folder
      if ($null -eq $folder) { continue }
      $result += [pscustomobject]@{
        Win  = $w
        HWND = [int64]$w.HWND
        Key  = Format-Key $folder.Self.Path
      }
    } catch { }
  }
  return $result
}

$folder    = if ($Select) { Split-Path -Parent -Path $Path } else { $Path }
$folderKey = Format-Key $folder

$before = @{}
foreach ($w in Get-ExplorerWindows) { $before[$w.HWND] = $true }

$reused = $false
if ($Reuse) {
  $candidate = Get-ExplorerWindows | Select-Object -First 1
  if ($candidate) {
    try {
      $candidate.Win.Navigate2($folder)
      $reused = $true
    } catch { }
  }
}

if (-not $reused) {
  # /select, and the path are ONE argument — a space after the comma makes
  # explorer.exe drop the path and open Documents instead.
  $argument = if ($Select) { "/select,`"$Path`"" } else { "`"$Path`"" }
  Start-Process -FilePath 'explorer.exe' -ArgumentList $argument
}

# Matching a pre-existing window on the target folder is only correct once
# Explorer has had a chance to create its new one — otherwise revealing the
# same folder twice would raise the stale window and leave the fresh one
# behind. Reuse skips the wait because there is no new window by definition.
$deadline      = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)
$existingAfter = [datetime]::UtcNow.AddMilliseconds(1500)
$hwnd          = [int64]0

while ([datetime]::UtcNow -lt $deadline) {
  $windows = Get-ExplorerWindows
  $match = $windows | Where-Object { -not $before.ContainsKey($_.HWND) -and $_.Key -eq $folderKey } | Select-Object -First 1
  if (-not $match) {
    $match = $windows | Where-Object { -not $before.ContainsKey($_.HWND) } | Select-Object -First 1
  }
  if (-not $match -and ($reused -or [datetime]::UtcNow -ge $existingAfter)) {
    $match = $windows | Where-Object { $_.Key -eq $folderKey } | Select-Object -First 1
  }
  if ($match) { $hwnd = $match.HWND; break }
  Start-Sleep -Milliseconds 100
}

if ($hwnd -eq 0) { exit 1 }

# Explorer paints the window a beat after it registers with the shell; raising
# it too early loses the race against its own activation.
Start-Sleep -Milliseconds 120
if ([LibNvimReveal]::Raise([IntPtr]$hwnd)) { exit 0 }
exit 1
