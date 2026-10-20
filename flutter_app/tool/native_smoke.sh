#!/usr/bin/env bash
# Verifies an actual Flutter Linux GTK window under Xvfb and Openbox.
set -euo pipefail
cd "$(dirname "$0")/.."
app="./build/linux/x64/release/bundle/qingfan"
test -x "$app" || { echo "Release executable not found: $app" >&2; exit 1; }
command -v wmctrl >/dev/null
openbox --sm-disable >/tmp/qingfan-openbox.log 2>&1 &
wm_pid=$!
picom --backend xrender --no-vsync --no-fading-openclose >/tmp/qingfan-picom.log 2>&1 &
compositor_pid=$!
watch_pid=""
cleanup() {
  [[ -n "$watch_pid" ]] && kill "$watch_pid" >/dev/null 2>&1 || :
  kill "$compositor_pid" >/dev/null 2>&1 || :
  kill "$wm_pid" >/dev/null 2>&1 || :
}
trap cleanup EXIT
sleep 0.7
kill -0 "$compositor_pid" >/dev/null 2>&1 ||
  { cat /tmp/qingfan-picom.log >&2; echo 'X11_COMPOSITOR_UNAVAILABLE' >&2; exit 1; }
echo 'X11_COMPOSITOR_READY'
# Dark wallpaper exposes opaque white square backgrounds in otherwise round
# glass clocks. This makes transparency objectively testable.
xsetroot -solid '#34203B'
seen_file="$(mktemp)"
trap 'rm -f "$seen_file"; cleanup' EXIT
(
  for _ in $(seq 1 150); do
    count="$(wmctrl -l | grep -E '青番|qingfan' | wc -l || :)"
    echo "$count" >> "$seen_file"
    sleep .09
  done
) &
watch_pid=$!
# Launch a second instance while the main native window is alive. It must
# detect the held OS lock, return immediately, and never create another view.
QINGFAN_NATIVE_SMOKE=1 timeout 35s "$app" >native-smoke.log 2>&1 &
main_pid=$!
# Wait for the primary window to become real and publish a geometry result
# BEFORE attempting a second start. Racing both GTK runners at boot would
# only test process scheduling and can reverse which process owns the lock.
ready=0
for _ in $(seq 1 100); do
  if grep -q 'NATIVE_SMOKE_OBSERVED full' native-smoke.log; then
    ready=1
    break
  fi
  if ! kill -0 "$main_pid" >/dev/null 2>&1; then break; fi
  sleep .10
done
if [[ "$ready" != "1" ]]; then
  cat native-smoke.log
  echo "NATIVE_PRIMARY_STARTUP_FAILED" >&2
  exit 1
fi
set +e
timeout 15s "$app" >native-second-instance.log 2>&1
second_status=$?
wait "$main_pid"
status=$?
set -e
echo "NATIVE_SECOND_INSTANCE_EXIT=$second_status"
cat native-smoke.log
if [[ "$status" -ne 0 ]]; then
  echo "NATIVE_SMOKE_FAILED exit=$status" >&2
  exit "$status"
fi
[[ "$second_status" -eq 0 ]] ||
  { cat native-second-instance.log >&2; echo "SECOND_INSTANCE_FAILED" >&2; exit 1; }
grep -q 'QINGFAN_ALREADY_RUNNING' native-second-instance.log ||
  { cat native-second-instance.log >&2; echo "SECOND_INSTANCE_LOCK_FAILED" >&2; exit 1; }
echo 'NATIVE_SINGLE_INSTANCE_PASS'
grep -q 'NATIVE_SMOKE_PASS' native-smoke.log
for scene in full mini full_return tasks close_tasks; do
  grep -q "NATIVE_SMOKE_SIZE $scene:" native-smoke.log ||
    { echo "Missing native geometry check: $scene" >&2; exit 1; }
done
if [[ "${QINGFAN_NATIVE_CAPTURE:-0}" == "1" ]]; then
  for scene in full mini full_return tasks close_tasks; do
    direct="native-shots/$scene.png"
    root="native-shots/$scene-root.png"
    [[ -s "$direct" && -s "$root" ]] ||
      { echo "NATIVE_SCREENSHOT_MISSING $scene" >&2; exit 1; }
    direct_entropy="$(identify -format '%[entropy]' "$direct")"
    root_entropy="$(identify -format '%[entropy]' "$root")"
    echo "NATIVE_SCREENSHOT_ENTROPY $scene direct=$direct_entropy root=$root_entropy"
    awk -v direct="$direct_entropy" -v root="$root_entropy" \
      'BEGIN { exit !((direct > 0.01) || (root > 0.01)) }' ||
      { echo "NATIVE_SCREENSHOT_BLANK $scene direct=$direct_entropy root=$root_entropy" >&2; exit 1; }
  done
  echo 'NATIVE_VISUAL_CONTENT_PASS'
  # Root framebuffer captures the composited display: at the round clock's
  # top-left corner we must see the dark desktop, not an opaque application
  # rectangle. Require both full and mini clocks to pass the alpha test.
  for scene in full mini; do
    corner="$(convert "native-shots/$scene-root.png" -format '%[fx:int(255*u.p{2,2}.r)]' info:)"
    echo "NATIVE_ALPHA_CORNER $scene red=$corner"
    [[ "$corner" -lt 125 ]] ||
      { echo "NATIVE_ALPHA_CORNER_OPAQUE $scene red=$corner" >&2; exit 1; }
  done
  echo 'NATIVE_ROUND_WINDOW_ALPHA_PASS'
fi
max_count="$(sort -nr "$seen_file" | head -1)"
echo "NATIVE_SMOKE_MAX_WINDOWS=$max_count"
[[ "$max_count" == "1" ]] ||
  { echo "Expected one and only one Qingfan top-level window" >&2; exit 1; }
echo 'NATIVE_LINUX_X11_ACCEPTANCE_PASS'
