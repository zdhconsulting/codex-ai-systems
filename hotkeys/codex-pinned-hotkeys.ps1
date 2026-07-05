param(
  [string]$ConfigPath = "$env:USERPROFILE\.codex\hotkeys\codex-pinned-hotkeys.config.json",
  [switch]$Once
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class CodexPinnedHotkeyNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}

public class CodexPinnedHotkeyWindow : NativeWindow, IDisposable {
    public event Action<int> HotkeyPressed;
    private const int WM_HOTKEY = 0x0312;

    public CodexPinnedHotkeyWindow() {
        CreateHandle(new CreateParams());
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && HotkeyPressed != null) {
            HotkeyPressed(m.WParam.ToInt32());
        }
        base.WndProc(ref m);
    }

    public void Dispose() {
        DestroyHandle();
    }
}
"@

function Read-Config {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing hotkey config: $Path"
  }
  Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-HotkeyLog {
  param([object]$Config, [string]$Message)
  try {
    $path = [Environment]::ExpandEnvironmentVariables([string]$Config.logPath)
    $dir = Split-Path -Parent $path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $path -Value ("{0} {1}" -f (Get-Date -Format o), $Message)
  } catch {
    # Hotkeys should never fail just because logging failed.
  }
}

function Get-CodexWindowHandle {
  param([object]$Config)
  $title = [string]$Config.windowTitle
  $proc = Get-Process Codex -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -eq $title -or $_.MainWindowTitle -like "*$title*") } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

  if (-not $proc) {
    $proc = Get-Process Codex -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
  }

  if ($proc) { return [IntPtr]$proc.MainWindowHandle }
  [IntPtr]::Zero
}

function Invoke-PinnedClick {
  param([int]$Index)

  $config = Read-Config -Path $script:ConfigPath
  if (-not $config.enabled) { return }

  $hwnd = Get-CodexWindowHandle -Config $config
  if ($hwnd -eq [IntPtr]::Zero) {
    Write-HotkeyLog -Config $config -Message "F$Index ignored: Codex window not found"
    return
  }

  if ($config.restoreIfMinimized) {
    [CodexPinnedHotkeyNative]::ShowWindow($hwnd, 9) | Out-Null
  }

  [CodexPinnedHotkeyNative]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 80

  $rect = New-Object CodexPinnedHotkeyNative+RECT
  [CodexPinnedHotkeyNative]::GetWindowRect($hwnd, [ref]$rect) | Out-Null

  $x = $rect.Left + [int]$config.sidebarClickX
  $y = $rect.Top + [int]$config.firstPinnedRowY + (($Index - 1) * [int]$config.rowHeight)

  [CodexPinnedHotkeyNative]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 25
  [CodexPinnedHotkeyNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
  [CodexPinnedHotkeyNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Write-HotkeyLog -Config $config -Message "F$Index clicked pinned row $Index at screen $x,$y"
}

$script:ConfigPath = $ConfigPath

if ($Once) {
  Invoke-PinnedClick -Index 1
  return
}

$config = Read-Config -Path $ConfigPath
$count = [Math]::Max(1, [Math]::Min(12, [int]$config.hotkeyCount))
$form = New-Object CodexPinnedHotkeyWindow
$registered = New-Object System.Collections.Generic.List[int]
$modNoRepeat = 0x4000

try {
  for ($i = 1; $i -le $count; $i++) {
    $vk = 0x70 + ($i - 1)
    if ([CodexPinnedHotkeyNative]::RegisterHotKey($form.Handle, $i, $modNoRepeat, $vk)) {
      $registered.Add($i)
    } else {
      Write-HotkeyLog -Config $config -Message "Failed to register F$i"
    }
  }

  $form.add_HotkeyPressed({ param($id) Invoke-PinnedClick -Index $id })
  Write-HotkeyLog -Config $config -Message "Started pinned-order hotkeys: F1-F$count"
  [System.Windows.Forms.Application]::Run()
}
finally {
  foreach ($id in $registered) {
    [CodexPinnedHotkeyNative]::UnregisterHotKey($form.Handle, $id) | Out-Null
  }
  $form.Dispose()
  Write-HotkeyLog -Config $config -Message "Stopped pinned-order hotkeys"
}
