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
$process = Start-Process -FilePath $exe -ArgumentList '--native-smoke' -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
# Save pixels from the actual desktop session for later visual inspection.
# Screenshot availability is environment-dependent and never substitutes for
# the strict native window and process checks below.
Start-Sleep -Milliseconds 1100
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
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
