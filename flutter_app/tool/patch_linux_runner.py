#!/usr/bin/env python3
"""Patch Flutter 3.47 Linux runner for Qingfan's actual compact native window.

The Flutter template hardcodes a visible 1280x720 GTK window before Dart runs.
The window_manager 0.5.x Linux plugin cannot reliably resize a nonresizable
window away from that default. We keep the original template's behavior
auditable via an explicit, assertion-checked, version-pinned patch.
"""
from pathlib import Path

runner = Path(__file__).resolve().parents[1] / "linux" / "runner" / "my_application.cc"
source = runner.read_text(encoding="utf-8")

old_default = "1280, 720"
if source.count(old_default) == 1:
    source = source.replace(old_default, "376, 408", 1)
elif source.count("376, 408") != 1:
    raise SystemExit("Flutter Linux runner default size is not recognized")

# Flutter 3.47 already delays the GTK top-level show until the first
# Flutter frame, in first_frame_cb(). Older templates showed the window early.
old_show = "gtk_widget_show(GTK_WIDGET(window));"
if source.count(old_show) == 1:
    source = source.replace(
        old_show, "gtk_widget_realize(GTK_WIDGET(window));", 1
    )
elif ('gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)))'
      not in source):
    raise SystemExit("Flutter Linux runner display timing not recognized")

# The generated runner explicitly paints its own black surface BEFORE Dart
# applies WindowOptions. Give the underlying Flutter surface an alpha channel.
old_background = 'gdk_rgba_parse(&background_color, "#000000");'
new_background = 'gdk_rgba_parse(&background_color, "#00000000");'
if source.count(old_background) == 1:
    source = source.replace(old_background, new_background, 1)
elif source.count(new_background) != 1:
    raise SystemExit("Flutter Linux background color template not recognized")

runner.write_text(source, encoding="utf-8")
print("LINUX_RUNNER_PATCH_PASS: default=376x408, first-frame show, alpha surface")
