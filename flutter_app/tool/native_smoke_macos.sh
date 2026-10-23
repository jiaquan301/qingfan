#!/usr/bin/env bash
# Launch the actual release .app in the macOS runner's graphical session.
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/macos/Build/Products/Release/qingfan.app"
test -x "$app/Contents/MacOS/qingfan"
swiftc tool/macos_windows.swift -o "$RUNNER_TEMP/qingfan-macos-window-inspector"
export QINGFAN_MAC_WINDOW_INSPECTOR="$RUNNER_TEMP/qingfan-macos-window-inspector"
python3 - <<'PY'
import os
import pathlib
import re
import subprocess
import sys
import time

exe = pathlib.Path("build/macos/Build/Products/Release/qingfan.app/Contents/MacOS/qingfan")
proc = subprocess.Popen(
    [str(exe), "--native-smoke"], stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, text=True,
)
# Native WindowServer capture. On a hosted runner recording permissions can
# restrict this operation; the process/geometry checks remain mandatory.
time.sleep(1.5)
inspect = subprocess.run(
    [os.environ["QINGFAN_MAC_WINDOW_INSPECTOR"]],
    capture_output=True, text=True, timeout=10,
)
print(inspect.stdout.strip())
pathlib.Path("macos-window-inspection.log").write_text(inspect.stdout + inspect.stderr, encoding="utf-8")
ids = re.findall(r"QINGFAN_MAC_WINDOW id=(\d+) onscreen=true", inspect.stdout)
if ids:
    shot = subprocess.run(
        ["screencapture", "-x", "-l", ids[0], "macos-native-window.png"],
        capture_output=True, text=True,
    )
    if shot.returncode == 0 and pathlib.Path("macos-native-window.png").is_file():
        print("MACOS_NATIVE_WINDOW_SCREENSHOT_CAPTURED")
    else:
        print(f"MACOS_NATIVE_WINDOW_SCREENSHOT_UNAVAILABLE: {shot.stderr.strip()}")
else:
    print("MACOS_NATIVE_WINDOW_NOT_ON_SCREEN")
shot = subprocess.run(
    ["screencapture", "-x", "macos-native-desktop.png"],
    capture_output=True, text=True,
)
if shot.returncode == 0 and pathlib.Path("macos-native-desktop.png").stat().st_size > 2048:
    print("MACOS_NATIVE_SCREENSHOT_CAPTURED")
else:
    print(f"MACOS_NATIVE_SCREENSHOT_UNAVAILABLE: {shot.stderr.strip()}")
try:
    stdout, stderr = proc.communicate(timeout=90)
except subprocess.TimeoutExpired as exc:
    proc.kill()
    proc.communicate()
    print("MACOS_NATIVE_TIMEOUT: the app did not close after smoke", file=sys.stderr)
    raise SystemExit(1) from exc
log = stdout + "\n" + stderr
pathlib.Path("macos-native-smoke.log").write_text(log, encoding="utf-8")
print(log)
if proc.returncode != 0:
    raise SystemExit(f"MACOS_NATIVE_EXIT_FAILED: {proc.returncode}")
for marker in [
    "NATIVE_SMOKE_SIZE dial:",
    "NATIVE_SMOKE_SIZE dial_return:",
    "NATIVE_SMOKE_SIZE menu:",
    "NATIVE_SMOKE_SIZE tasks:",
    "NATIVE_SMOKE_SIZE tasks_50:",
    "NATIVE_SMOKE_SIZE settings:",
    "NATIVE_TOPMOST_SURFACE dial reported=true",
    "NATIVE_TOPMOST_SURFACE settings reported=true",
    "NATIVE_TOPMOST_RESET reported=false",
    "NATIVE_SMOKE_TOPMOST_ALL_SURFACES_PASS",
    "NATIVE_SMOKE_PASS",
]:
    if marker not in log:
        raise SystemExit(f"MACOS_NATIVE_MISSING: {marker}")
print("MACOS_NATIVE_APP_ACCEPTANCE_PASS")
PY
