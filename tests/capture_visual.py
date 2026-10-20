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
                    # Reject a mapped-but-not-painted black frame. Xvfb can
                    # expose a new toplevel before its Cairo draw callback.
                    has_alpha = channels != 4 or pixels[pos + 3] > 32
                    has_color = max(pixels[pos:pos + 3]) > 60
                    visible_samples += bool(has_alpha and has_color)
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


def assert_task_footer_visible(window):
    drain()
    width, height = window.get_size()
    button = window.task_primary_button
    pos = button.translate_coordinates(window, 0, 0)
    allocated = button.get_allocation()
    panel = window.task_panel
    inside = panel.get_children()[-1]
    scroller = window.scroller
    print('TASK_ALLOCATIONS', {
        'window': (width, height),
        'panel': (panel.get_allocated_width(), panel.get_allocated_height()),
        'inside': (inside.get_allocated_width(), inside.get_allocated_height()),
        'scroller': (scroller.get_allocated_width(), scroller.get_allocated_height()),
        'button': (pos, allocated.width, allocated.height),
    }, flush=True)
    if pos is None or pos[1] < 0 or pos[1] + allocated.height + 6 > height:
        raise RuntimeError(
            f'Task primary button clipped by window: {pos}, '
            f'button height={allocated.height}, window height={height}')


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
    print('TASK_PRIMARY', {
        'current_id': w.model.current_id,
        'tasks': len(w.model.pending_tasks),
        'sensitive': w.task_primary_button.get_sensitive(),
        'label': w.task_primary_button.get_label(),
    }, flush=True)
    if w.model.current_id is None or not w.task_primary_button.get_sensitive():
        raise RuntimeError('Selected task must enable primary focus action')
    print('TASK_BUTTON_STATE', {
        'effective_sensitive': w.task_primary_button.is_sensitive(),
        'state_flags': int(w.task_primary_button.get_state_flags()),
    }, flush=True)
    w.task_primary_button.queue_draw()
    drain()
    time.sleep(0.15)
    drain()
    capture(w, 'tasks')
    assert_task_footer_visible(w)

    # Keep a real 50-task fixture in visual evidence: the manager must remain
    # the same size and expose a working internal scrollbar.
    for index in range(49):
        w.model.add(f'长清单任务 {index + 2:02d}')
    w.refresh_tasks()
    drain()
    adjustment = w.scroller.get_vadjustment()
    if adjustment.get_upper() <= adjustment.get_page_size():
        raise RuntimeError('50-task list did not activate its internal scrollbar')
    capture(w, 'long_tasks')
    assert_task_footer_visible(w)
    w.destroy()


if __name__ == '__main__':
    main()
