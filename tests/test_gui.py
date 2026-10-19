"""Run with /usr/bin/python3 on a GTK 3 desktop (or under xvfb-run)."""
import os
import gc
import uuid
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

try:
    from pomodoro.app import Application, Window, Gtk, Gdk, Gio
    HAS_DISPLAY = Gtk.init_check()[0]
except (ImportError, ValueError):
    HAS_DISPLAY = False


if os.environ.get('QINGFAN_REQUIRE_GUI') == '1' and not HAS_DISPLAY:
    raise RuntimeError('发布检查失败：无法连接 GTK 图形显示服务；GUI 测试不得跳过')


def create_test_application():
    app = Application()
    # Each fixture gets its own valid D-Bus name. Register as a normal
    # unique app so Gtk.Application emits ::startup before windows are added.
    app.set_application_id(f'app.qingfan.Test.t{uuid.uuid4().hex}')
    app.set_flags(Gio.ApplicationFlags.FLAGS_NONE)
    return app


_shared_app = None


def registered_test_application():
    """GTK/D-Bus process lifetime is shared; isolate windows and state per test."""
    global _shared_app
    if _shared_app is None:
        app = create_test_application()
        if not app.register(None):
            raise RuntimeError('GTK application registration failed')
        _shared_app = app
    return _shared_app


@unittest.skipUnless(HAS_DISPLAY, 'GTK 3 graphical display unavailable')
class GuiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, XDG_DATA_HOME=self.temp.name)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.app = registered_test_application()
        self.addCleanup(self._cleanup_application)
        self.window = Window(self.app)
        self.addCleanup(self.window.destroy)
        self.window._set_mode(False)
        for name in ('写方案', '检查材料', '发布'):
            self.window.entry.set_text(name)
            self.window.add_task()

    def _cleanup_application(self):
        # addCleanup also runs if register() or Window() raises in setUp.
        for window in self.app.get_windows():
            window.destroy()
        # Do not quit the GApplication between tests. GTK's DBus registration
        # is process-scoped; tearing it down causes subsequent registrations
        # to fail even with different, valid application IDs.
        self.app = None
        self.window = None
        gc.collect()

    def editor(self, row=0):
        widgets = self.window.rows_box.get_children()[row].get_children()
        stack = next(w for w in widgets if isinstance(w, Gtk.Stack))
        stack.get_child_by_name('title').clicked()
        return stack.get_child_by_name('edit')

    def test_inline_edit_save_and_escape_cancel(self):
        field = self.editor()
        field.set_text('修改后的任务')
        field.emit('activate')
        self.assertEqual(self.window.model.tasks[0]['title'], '修改后的任务')
        field = self.editor()
        field.set_text('不应保存')
        self.window.on_shortcut(None, SimpleNamespace(keyval=Gdk.KEY_Escape, state=0))
        self.assertEqual(self.window.model.tasks[0]['title'], '修改后的任务')
        self.assertFalse(self.window.compact)

    def test_blank_edit_keeps_original(self):
        field = self.editor()
        field.set_text('  ')
        field.emit('activate')
        self.assertEqual(self.window.model.tasks[0]['title'], '写方案')

    def test_delete_current_pauses_and_undo_restores(self):
        tid = self.window.model.tasks[0]['id']
        self.window.model.start_pause()
        self.window.remove_task(tid)
        self.assertFalse(self.window.model.running())
        self.assertIsNone(self.window.model.current_id)
        self.assertTrue(self.window.undo_bar.get_visible())
        self.window.undo_delete()
        self.assertEqual(self.window.model.tasks[0]['id'], tid)
        self.assertEqual(self.window.model.current_id, tid)
        self.assertFalse(self.window.model.running())

    def test_refresh_destroys_old_rows(self):
        old = self.window.rows_box.get_children()[0]
        destroyed = []
        old.connect('destroy', lambda *_: destroyed.append(True))
        self.window.refresh_tasks()
        self.assertEqual(destroyed, [True])
        self.assertEqual(len(self.window.rows_box.get_children()), 3)

    def test_task_update_does_not_request_window_move(self):
        with patch.object(self.window, 'move') as move:
            self.window.refresh_tasks()
            self.window._set_mode(True)
            self.window._set_mode(False)
            move.assert_not_called()

    def test_startup_has_real_content_not_just_titlebar(self):
        self.window.present()
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        self.assertIsNotNone(self.window.get_child())
        self.assertIsNotNone(self.window.get_titlebar())
        self.assertTrue(self.window.clock.get_visible())
        self.assertEqual(self.window.clock.get_text(), '25:00')
        self.assertEqual(len(self.window.rows_box.get_children()), 3)
        self.assertIn(self.window, self.app.get_windows())

    def test_failed_construction_does_not_register_empty_window(self):
        before = list(self.app.get_windows())
        with patch.object(Window, '_build', side_effect=TypeError('bad GTK call')):
            with self.assertRaisesRegex(TypeError, 'bad GTK call'):
                Window(self.app)
        self.assertEqual(list(self.app.get_windows()), before)

    def test_shared_application_stays_registered(self):
        self.assertIs(self.app, registered_test_application())
        self.assertTrue(self.app.get_is_registered())
