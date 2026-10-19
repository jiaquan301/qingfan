#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON=/usr/bin/python3
if ! "$PYTHON" -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("Gdk", "3.0"); from gi.repository import Gtk, GdkPixbuf' >/dev/null 2>&1; then
  printf '%s\n' '缺少 Ubuntu GTK 3 运行环境。请先执行：' \
    'sudo apt update && sudo apt install python3-gi gir1.2-gtk-3.0 librsvg2-common' >&2
  exit 1
fi
APP_DIR="$HOME/.local/share/qingfan-app"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"
cp -R "$BASE/pomodoro" "$APP_DIR/"
cp -R "$BASE/assets" "$APP_DIR/"
cp "$BASE/run.sh" "$APP_DIR/run.sh"
chmod +x "$APP_DIR/run.sh"
cp "$BASE/assets/qingfan.svg" "$ICON_DIR/app.qingfan.Pomodoro.svg"
"$PYTHON" - "$APP_DIR/run.sh" "$DESKTOP_DIR/app.qingfan.Pomodoro.desktop" <<'PYDESKTOP'
import sys
from gi.repository import GLib

launcher, destination = sys.argv[1:]
# KeyFile handles desktop-entry string escaping; Exec also needs argument quoting.
quoted = launcher.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
entry = GLib.KeyFile()
values = {
    'Type': 'Application', 'Name': '青番', 'GenericName': '番茄钟',
    'Comment': '一次专注一件事', 'Exec': '"' + quoted + '"',
    'Icon': 'app.qingfan.Pomodoro', 'Terminal': 'false',
    'Categories': 'Utility;Office;', 'StartupNotify': 'true',
    'Keywords': 'Pomodoro;Focus;Timer;番茄钟;专注;',
}
for key, value in values.items():
    entry.set_string('Desktop Entry', key, value)
entry.save_to_file(destination)
PYDESKTOP
chmod 644 "$DESKTOP_DIR/app.qingfan.Pomodoro.desktop"
# Retire the desktop shortcut from V1 (never touches task data).
rm -f -- "$HOME/.local/share/applications/qingfan.desktop"
printf '\n%s\n' '青番 2.0 已安装。可从应用菜单搜索「青番」启动。' \
  '数据保留在 ~/.local/share/qingfan/state.json，兼容 1.x 版本。'
