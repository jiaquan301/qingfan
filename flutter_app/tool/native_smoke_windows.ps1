param([string]$Executable = '')
# Exercise the real Flutter Windows release window, not only widget tests.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$exe = if ($Executable) { $Executable } else {
  Join-Path (Get-Location) 'build/windows/x64/runner/Release/qingfan.exe'
}
if (-not (Test-Path $exe)) { throw "Windows executable missing: $exe" }
$stdout = Join-Path (Get-Location) 'windows-native-smoke.log'
$stderr = Join-Path (Get-Location) 'windows-native-stderr.log'
# Prepare Win32 capture before startup, so the short-lived smoke window
# remains alive during the actual pixel capture.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class QingfanCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
'@
$process = Start-Process -FilePath $exe -ArgumentList '--native-smoke' -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
# Both the desktop and the specific Qingfan HWND are captured. The runner's
# terminal may obscure the desktop; PrintWindow provides a second, focused
# view that can be reviewed independently.
try {
  $hwnd = [IntPtr]::Zero
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    $process.Refresh()
    $hwnd = $process.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 100
  }
  if ($hwnd -eq [IntPtr]::Zero) { throw 'No native Win32 main window handle' }
  Write-Output "WINDOWS_NATIVE_HWND=$hwnd"
  [QingfanCapture]::ShowWindow($hwnd, 5) | Out-Null
  $activated = [QingfanCapture]::SetForegroundWindow($hwnd)
  Write-Output "WINDOWS_NATIVE_ACTIVATED=$activated"
  Start-Sleep -Milliseconds 260
  $rect = [QingfanCapture+Rect]::new()
  if (-not [QingfanCapture]::GetWindowRect($hwnd, [ref]$rect)) { throw 'Unable to read Win32 window bounds' }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -lt 80 -or $height -lt 80) { throw "Invalid native dimensions $width x $height" }
  $windowBmp = [System.Drawing.Bitmap]::new($width, $height)
  $windowGraphics = [System.Drawing.Graphics]::FromImage($windowBmp)
  try {
    $dc = $windowGraphics.GetHdc()
    try { $printed = [QingfanCapture]::PrintWindow($hwnd, $dc, 2) }
    finally { $windowGraphics.ReleaseHdc($dc) }
    $windowBmp.Save((Join-Path (Get-Location) 'windows-native-window.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "WINDOWS_NATIVE_WINDOW_SCREENSHOT_CAPTURED=$printed"
  } finally {
    $windowGraphics.Dispose()
    $windowBmp.Dispose()
  }
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [System.Drawing.Bitmap]::new($screen.Width, $screen.Height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $screen.Size)
    $bitmap.Save((Join-Path (Get-Location) 'windows-native-desktop.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output 'WINDOWS_NATIVE_SCREENSHOT_CAPTURED'
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
} catch {
  Write-Warning "WINDOWS_NATIVE_SCREENSHOT_UNAVAILABLE: $_"
}
try {
  Wait-Process -Id $process.Id -Timeout 90 -ErrorAction Stop
} catch {
  Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  throw "WINDOWS_NATIVE_TIMEOUT: release process did not exit"
}
$process.Refresh()
$log = (Get-Content -Raw -Path $stdout) + "`n" + (Get-Content -Raw -Path $stderr)
Write-Output $log
if ($process.ExitCode -ne 0) { throw "WINDOWS_NATIVE_EXIT_FAILED: $($process.ExitCode)" }
$required = @(
  'NATIVE_SMOKE_SIZE full:',
  'NATIVE_SMOKE_SIZE mini:',
  'NATIVE_SMOKE_SIZE tasks:',
  'NATIVE_SMOKE_SIZE tasks_50:',
  'NATIVE_SMOKE_SIZE settings:',
  'NATIVE_TOPMOST_SURFACE mini reported=true',
  'NATIVE_TOPMOST_SURFACE settings reported=true',
  'NATIVE_TOPMOST_RESET reported=false',
  'NATIVE_SMOKE_TOPMOST_ALL_SURFACES_PASS',
  'NATIVE_SMOKE_PASS'
)
foreach ($marker in $required) {
  if (-not $log.Contains($marker)) { throw "WINDOWS_NATIVE_MISSING: $marker" }
}
Write-Output 'WINDOWS_NATIVE_APP_ACCEPTANCE_PASS'
