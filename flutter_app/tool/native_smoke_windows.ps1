# Exercise the real Flutter Windows release window, not only widget tests.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$exe = Join-Path (Get-Location) 'build/windows/x64/runner/Release/qingfan.exe'
if (-not (Test-Path $exe)) { throw "Windows release executable missing" }
$stdout = Join-Path (Get-Location) 'windows-native-smoke.log'
$stderr = Join-Path (Get-Location) 'windows-native-stderr.log'
$process = Start-Process -FilePath $exe -ArgumentList '--native-smoke' -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
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
