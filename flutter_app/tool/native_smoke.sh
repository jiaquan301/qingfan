#!/usr/bin/env bash
# Flutter V3 single 104px crystal dial acceptance on a real composited X11.
set -euo pipefail
cd "$(dirname "$0")/.."
app="./build/linux/x64/release/bundle/qingfan"
test -x "$app"
openbox --sm-disable >/tmp/qingfan-openbox.log 2>&1 &
wm_pid=$!
picom --backend xrender --no-vsync --no-fading-openclose >/tmp/qingfan-picom.log 2>&1 &
compositor_pid=$!
cleanup() {
  kill "$compositor_pid" "$wm_pid" 2>/dev/null || true
}
trap cleanup EXIT
sleep .8
kill -0 "$compositor_pid"
xsetroot -solid '#34203B'
xdotool mousemove 10 10
QINGFAN_NATIVE_SMOKE=1 QINGFAN_NATIVE_DRAG=1 timeout 55s "$app" > native-smoke.log 2>&1 &
app_pid=$!
ready=0
for _ in $(seq 1 100); do
  if grep -q "NATIVE_SMOKE_OBSERVED dial " native-smoke.log; then ready=1; break; fi
  kill -0 "$app_pid" 2>/dev/null || break
  sleep .1
done
if [[ "$ready" != 1 ]]; then cat native-smoke.log; exit 1; fi
for _ in $(seq 1 100); do
  if grep -q 'NATIVE_DRAG_READY dial' native-smoke.log; then break; fi
  sleep .08
done
grep -q 'NATIVE_DRAG_READY dial' native-smoke.log
geometry="$(wmctrl -lG | grep -E '青番|qingfan' | head -1)"
read -r x y w h < <(awk '{print $3, $4, $5, $6}' <<< "$geometry")
# Drag left outer ring, never the centre, task control or menu.
xdotool mousemove --sync $((x + 9)) $((y + h / 2))
xdotool mousedown 1
sleep .12
xdotool mousemove --sync $((x + 76)) $((y + h / 2 + 40))
sleep .15
xdotool mousemove --sync $((x + 125)) $((y + h / 2 + 75))
sleep .12
xdotool mouseup 1
sleep .2
geometry="$(wmctrl -lG | grep -E '青番|qingfan' | head -1)"
read -r nx ny < <(awk '{print $3, $4}' <<< "$geometry")
echo "NATIVE_DRAG_POSITION dial: ($x,$y) -> ($nx,$ny)"
if (( nx - x < 25 && x - nx < 25 && ny - y < 25 && y - ny < 25 )); then
  echo 'NATIVE_DRAG_FAILED' >&2
  exit 1
fi
echo 'NATIVE_DRAG_PASS dial'
timeout 12s "$app" > native-second-instance.log 2>&1
grep -q QINGFAN_ALREADY_RUNNING native-second-instance.log
wait "$app_pid"
echo NATIVE_SMOKE_EXIT_STATUS_PASS
grep -q NATIVE_SMOKE_PASS native-smoke.log
for scene in dial menu tasks tasks_50 settings dial_return; do
  grep -q "NATIVE_SMOKE_SIZE $scene:" native-smoke.log
done
if [[ "${QINGFAN_NATIVE_CAPTURE:-0}" == 1 ]]; then
  for scene in dial menu tasks tasks_50 settings dial_return; do
    for kind in "" "-root"; do
      file="native-shots/$scene$kind.png"
      [[ -s "$file" ]]
      entropy="$(identify -format '%[entropy]' "$file")"
      awk -v n="$entropy" 'BEGIN{ exit !(n > 0.01) }'
    done
  done
  corner="$(convert native-shots/dial-root.png -format '%[fx:int(255*u.p{2,2}.r)] %[fx:int(255*u.p{2,2}.g)] %[fx:int(255*u.p{2,2}.b)]' info:)"
  read -r r g b <<< "$corner"
  if (( r >= 185 && g >= 185 && b >= 185 )); then
    echo "NATIVE_ALPHA_CORNER_OPAQUE $corner" >&2
    exit 1
  fi
  echo NATIVE_ROUND_WINDOW_ALPHA_PASS
  for scene in tasks tasks_50 settings; do
    red="$(convert "native-shots/$scene-root.png" -format '%[fx:int(255*u.p{15,15}.r)]' info:)"
    [[ "$red" -gt 185 ]]
  done
  echo NATIVE_PANEL_SURFACE_PASS
fi
[[ "$(wmctrl -l | grep -E '青番|qingfan' | wc -l || true)" -le 1 ]]
echo NATIVE_SINGLE_INSTANCE_PASS
echo NATIVE_LINUX_X11_ACCEPTANCE_PASS
