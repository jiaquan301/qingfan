#!/bin/sh
# A release check must never report success after skipping GUI startup tests.
set -eu
cd -- "$(dirname -- "$0")"
export QINGFAN_REQUIRE_GUI=1
/usr/bin/python3 -m unittest discover -s tests -v
/usr/bin/python3 -m compileall -q pomodoro
sh -n run.sh install.sh uninstall.sh
