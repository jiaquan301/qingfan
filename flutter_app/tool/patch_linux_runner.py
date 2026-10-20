#!/usr/bin/env python3
"""Patch Flutter 3.47 Linux runner for Qingfan's actual compact native window.

The Flutter template hardcodes a visible 1280x720 GTK window before Dart runs.
The window_manager 0.5.x Linux plugin cannot reliably resize a nonresizable
window away from that default. We keep the original template's behavior
auditable via an explicit, assertion-checked, version-pinned patch.
"""
from pathlib import Path

runner = Path(__file__).resolve().parents[1] / "linux" / "my_application.cc"
source = runner.read_text(encoding="utf-8")

old_default = "1280, 720"
if source.count(old_default) == 1:
    source = source.replace(old_default, "376, 408", 1)
elif source.count("376, 408") != 1:
    raise SystemExit("Flutter Linux runner default size is not recognized")

old_show = "gtk_widget_show(GTK_WIDGET(window));"
new_realize = "gtk_widget_realize(GTK_WIDGET(window));"
if source.count(old_show) == 1:
    source = source.replace(old_show, new_realize, 1)
elif source.count(new_realize) != 1:
    raise SystemExit("Flutter Linux runner's early GtkWindow show is not recognized")

runner.write_text(source, encoding="utf-8")
print("LINUX_RUNNER_PATCH_PASS: default=376x408, deferred window show")
