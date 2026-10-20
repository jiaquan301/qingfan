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

# The GTK toplevel must use an RGBA visual before it gets realized,
# otherwise Flutter alpha would still composite against an opaque surface.
window_anchor = (
    "  GtkWindow* window =\n"
    "      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));"
)
rgba_visual = (
    window_anchor + "\n\n"
    "  GdkScreen* qingfan_screen = gtk_window_get_screen(window);\n"
    "  GdkVisual* qingfan_rgba = gdk_screen_get_rgba_visual(qingfan_screen);\n"
    "  if (qingfan_rgba && gdk_screen_is_composited(qingfan_screen)) {\n"
    "    gtk_widget_set_visual(GTK_WIDGET(window), qingfan_rgba);\n"
    "    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);\n"
    "  }"
)
if source.count(window_anchor) == 1:
    source = source.replace(window_anchor, rgba_visual, 1)
elif "GdkVisual* qingfan_rgba" not in source:
    raise SystemExit("Flutter GTK toplevel anchor not recognized")

# Alpha is carried through BOTH the GTK visual and FlView backing.
old_background = 'gdk_rgba_parse(&background_color, "#000000");'
new_background = 'gdk_rgba_parse(&background_color, "#00000000");'
if source.count(old_background) == 1:
    source = source.replace(old_background, new_background, 1)
elif source.count(new_background) != 1:
    raise SystemExit("Flutter Linux background color template not recognized")

runner.write_text(source, encoding="utf-8")
print("LINUX_RUNNER_PATCH_PASS: default=376x408, first-frame show, RGBA visual + transparent view")
