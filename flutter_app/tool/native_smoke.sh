#!/usr/bin/env bash
# Verifies an actual Flutter Linux GTK window under Xvfb and Openbox.
set -euo pipefail
cd "$(dirname "$0")/.."
app="./build/linux/x64/release/bundle/qingfan"
test -x "$app" || { echo "Release executable not found: $app" >&2; exit 1; }
command -v wmctrl >/dev/null
openbox --sm-disable >/tmp/qingfan-openbox.log 2>&1 &
wm_pid=$!
watch_pid=""
cleanup() {
  [[ -n "$watch_pid" ]] && kill "$watch_pid" >/dev/null 2>&1 || :
  kill "$wm_pid" >/dev/null 2>&1 || :
}
trap cleanup EXIT
sleep 0.7
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
set +e
QINGFAN_NATIVE_SMOKE=1 timeout 35s "$app" >native-smoke.log 2>&1
status=$?
set -e
cat native-smoke.log
if [[ "$status" -ne 0 ]]; then
  echo "NATIVE_SMOKE_FAILED exit=$status" >&2
  exit "$status"
fi
grep -q 'NATIVE_SMOKE_PASS' native-smoke.log
for scene in full mini full_return tasks close_tasks; do
  grep -q "NATIVE_SMOKE_SIZE $scene:" native-smoke.log ||
    { echo "Missing native geometry check: $scene" >&2; exit 1; }
done
max_count="$(sort -nr "$seen_file" | head -1)"
echo "NATIVE_SMOKE_MAX_WINDOWS=$max_count"
[[ "$max_count" == "1" ]] ||
  { echo "Expected one and only one Qingfan top-level window" >&2; exit 1; }
echo 'NATIVE_LINUX_X11_ACCEPTANCE_PASS'
