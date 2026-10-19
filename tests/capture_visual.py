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
    window.queue_draw()
    # A resize can be acknowledged by X11 before the first expose/draw frame.
    # Wait for the actual image instead of saving a transparent/black buffer.
    width, height = window.get_size()
    frame = None
    visible_samples = 0
    for _ in range(25):
        drain()
        Gdk.flush()
        native = window.get_window()
        if native is None:
            raise RuntimeError(f'{name}: window did not realize')
        frame = Gdk.pixbuf_get_from_window(native, 0, 0, width, height)
        if frame is not None:
            pixels = frame.get_pixels()
            stride = frame.get_rowstride()
            channels = frame.get_n_channels()
            visible_samples = 0
            for yy in range(0, height, 8):
                for xx in range(0, width, 8):
                    pos = yy * stride + xx * channels
                    # RGBA on compositing desktops, RGB in 24-bit Xvfb.
                    visible = (pixels[pos + 3] > 32 if channels == 4
                               else max(pixels[pos:pos + 3]) > 32)
                    visible_samples += bool(visible)
            if visible_samples >= 15:
                break
        time.sleep(0.04)
        window.queue_draw()
    if frame is None or visible_samples < 15:
        raise RuntimeError(f'{name}: actual GTK surface rendered blank')
    print(f'RENDERED_WINDOW_{name.upper()}_SIZE={width}x{height} SAMPLES={visible_samples}', flush=True)
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
