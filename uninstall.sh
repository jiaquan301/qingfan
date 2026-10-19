#!/bin/sh
set -eu
rm -rf -- "$HOME/.local/share/qingfan-app"
rm -f -- "${XDG_DATA_HOME:-$HOME/.local/share}/applications/app.qingfan.Pomodoro.desktop"
rm -f -- "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/app.qingfan.Pomodoro.svg"
printf '%s\n' '程序已卸载，原有任务数据仍保留在 ~/.local/share/qingfan/state.json。'
