#!/usr/bin/env bash
# Launch the actual release .app in the macOS runner's graphical session.
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/macos/Build/Products/Release/qingfan.app"
test -x "$app/Contents/MacOS/qingfan"
python3 - <<'PY'
import pathlib
import subprocess
import sys

exe = pathlib.Path("build/macos/Build/Products/Release/qingfan.app/Contents/MacOS/qingfan")
try:
    proc = subprocess.run(
        [str(exe), "--native-smoke"], capture_output=True, text=True, timeout=90
    )
except subprocess.TimeoutExpired as exc:
    print("MACOS_NATIVE_TIMEOUT: the app did not close after smoke", file=sys.stderr)
    raise SystemExit(1) from exc
log = proc.stdout + "\n" + proc.stderr
pathlib.Path("macos-native-smoke.log").write_text(log, encoding="utf-8")
print(log)
if proc.returncode != 0:
    raise SystemExit(f"MACOS_NATIVE_EXIT_FAILED: {proc.returncode}")
for marker in [
    "NATIVE_SMOKE_SIZE full:",
    "NATIVE_SMOKE_SIZE mini:",
    "NATIVE_SMOKE_SIZE tasks:",
    "NATIVE_SMOKE_SIZE tasks_50:",
    "NATIVE_SMOKE_SIZE settings:",
    "NATIVE_TOPMOST_SURFACE mini reported=true",
    "NATIVE_TOPMOST_SURFACE settings reported=true",
    "NATIVE_TOPMOST_RESET reported=false",
    "NATIVE_SMOKE_TOPMOST_ALL_SURFACES_PASS",
    "NATIVE_SMOKE_PASS",
]:
    if marker not in log:
        raise SystemExit(f"MACOS_NATIVE_MISSING: {marker}")
print("MACOS_NATIVE_APP_ACCEPTANCE_PASS")
PY
