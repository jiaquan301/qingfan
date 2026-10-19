"""Optional screenshot smoke test for CI's virtual GTK display.

Uses the actual widget surface, not a browser mock. Never runs as a unittest.
"""
import base64
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, Gtk

from pomodoro.app import Application, Window


def drain():
    for _ in range(60):
        if not Gtk.events_pending():
            break
        Gtk.main_iteration_do(False)


def capture(window, name):
    expected = {'focus': (326, 356), 'mini': (100, 100)}.get(name)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        drain()
        actual = window.get_size()
        valid = (actual == expected) if expected else (actual[0] >= 315 and actual[1] >= 215)
        if valid:
            break
        time.sleep(0.03)
    if not valid:
        raise RuntimeError(f'{name}: window content clipped, actual {window.get_size()}')
    native = window.get_window()
    if native is None:
        raise RuntimeError(f'{name}: window did not realize')
    width, height = window.get_size()
    print(f'RENDERED_WINDOW_{name.upper()}_SIZE={width}x{height}', flush=True)
    frame = Gdk.pixbuf_get_from_window(native, 0, 0, width, height)
    if frame is None:
        raise RuntimeError(f'{name}: GTK could not capture window surface')
    path = Path('visual-check') / (name + '.png')
    path.parent.mkdir(exist_ok=True)
    frame.savev(str(path), 'png', [], [])
    raw = path.read_bytes()
    print(f'VISUAL_{name.upper()}_BEGIN:{base64.b64encode(raw).decode("ascii")}:VISUAL_{name.upper()}_END', flush=True)


def main():
    app = Application()
    if not app.register(None):
        raise RuntimeError('Could not register GTK application')
    w = Window(app)
    w._set_mode(False)
    w.entry.set_text('完成产品设计评审')
    w.add_task()
    w._set_mode(True)
    drain()
    capture(w.orb_window, 'focus')
    w.orb_window.set_mini(True)
    drain()
    capture(w.orb_window, 'mini')
    w.orb_window.open_tasks()
    drain()
    capture(w, 'tasks')
    w.destroy()


if __name__ == '__main__':
    main()
