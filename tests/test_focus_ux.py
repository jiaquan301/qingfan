"""Focus-first model and GTK interaction regression tests (青番 1.0)."""
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from pomodoro.core import Model


class FocusModelTests(unittest.TestCase):
    def test_completed_focus_counts_once_and_persists(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            model = Model()
            model.add("写方案")
            model.current_id = model.tasks[0]["id"]
            model.start_pause(now=100)
            self.assertIsNone(model.tick(now=1599))
            self.assertEqual(model.tasks[0]["pomodoros"], 0)
            self.assertEqual(model.tick(now=1600), "focus")
            self.assertEqual(model.tasks[0]["pomodoros"], 1)
            self.assertIsNone(model.tick(now=2000))
            self.assertEqual(model.tasks[0]["pomodoros"], 1)
            model.save(path)
            self.assertEqual(Model.load(path).tasks[0]["pomodoros"], 1)

    def test_pause_reset_and_break_do_not_credit(self):
        model = Model()
        model.add("写代码")
        task_id = model.tasks[0]["id"]
        model.current_id = task_id
        model.start_pause(now=100)
        model.start_pause(now=200)
        model.reset()
        self.assertIsNone(model.tick(now=5000))
        self.assertEqual(model.tasks[0]["pomodoros"], 0)
        model.start_pause(now=6000)
        self.assertEqual(model.tick(now=7500), "focus")
        self.assertEqual(model.tasks[0]["pomodoros"], 1)
        model.start_pause(now=8000)
        self.assertEqual(model.tick(now=8300), "short")
        self.assertEqual(model.tasks[0]["pomodoros"], 1)

    def test_switch_task_resets_unfinished_focus_not_completed_counts(self):
        model = Model()
        model.add("A")
        model.add("B")
        a, b = (task["id"] for task in model.tasks)
        self.assertTrue(model.select(a))
        model.start_pause(now=100)
        model.start_pause(now=200)
        self.assertEqual(model.seconds(), 1400)
        self.assertTrue(model.select(b))
        self.assertFalse(model.running())
        self.assertEqual(model.seconds(), 1500)
        self.assertEqual(model.current_id, b)
        self.assertFalse(model.select("nonexistent"))
        self.assertFalse(model.select(b))
        self.assertEqual(model.current_id, b)

    def test_reorder_and_counts_survive_save(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            model = Model()
            for name in ("一", "二", "三"):
                model.add(name)
            first, second, third = [t["id"] for t in model.tasks]
            model.current_id = second
            model.tasks[1]["pomodoros"] = 7
            self.assertTrue(model.reorder(third, first))
            model.save(path)
            restored = Model.load(path)
            self.assertEqual([t["title"] for t in restored.tasks], ["三", "一", "二"])
            self.assertEqual(restored.current_id, second)
            self.assertEqual(restored.tasks[2]["pomodoros"], 7)


try:
    from test_gui import GuiTests, HAS_DISPLAY, Gtk, Gdk
except (ImportError, ValueError):
    HAS_DISPLAY = False
    GuiTests = unittest.TestCase


@unittest.skipUnless(HAS_DISPLAY, "GTK graphical display unavailable")
class FocusGuiTests(GuiTests):
    def test_start_collapses_list_pause_keeps_it_collapsed(self):
        self.assertFalse(self.window.compact)
        self.window.toggle_timer()
        self.assertTrue(self.window.model.running())
        self.assertTrue(self.window.compact)
        self.assertFalse(self.window.task_panel.get_visible())
        self.window.toggle_timer()
        self.assertFalse(self.window.model.running())
        self.assertTrue(self.window.compact)

    def test_checkbox_selects_and_no_play_button_exists(self):
        first, second = (task["id"] for task in self.window.model.tasks[:2])
        self.assertEqual(self.window.model.current_id, first)
        check = self.window.rows_box.get_children()[1].get_children()[0]
        self.assertIsInstance(check, Gtk.CheckButton)
        check.set_active(True)
        self.assertEqual(self.window.model.current_id, second)
        self.assertFalse(self.window.model.tasks[1]["done"])
        self.assertTrue(self.window.rows_box.get_children()[1].get_children()[0].get_active())
        self.assertFalse(self.window.rows_box.get_children()[0].get_children()[0].get_active())
        self.assertEqual(len(self.window.rows_box.get_children()[0].get_children()), 5)

    def test_task_selection_is_locked_during_running_focus(self):
        self.window.toggle_timer()
        self.window._set_mode(False)
        check = self.window.rows_box.get_children()[1].get_children()[0]
        self.assertFalse(check.get_sensitive())

    def test_switch_task_resets_partial_focus(self):
        self.window.model.start_pause(now=100)
        self.window.model.start_pause(now=200)
        self.assertEqual(self.window.model.seconds(), 1400)
        self.window.select_task(self.window.model.tasks[1]["id"])
        self.assertEqual(self.window.model.seconds(), 1500)
        self.assertFalse(self.window.model.running())

    def test_background_click_commits_edit_not_blocking_click(self):
        field = self.editor()
        field.set_text("更名后")
        with patch("pomodoro.app.Gtk.get_event_widget", return_value=self.window.clock):
            self.assertFalse(self.window.on_background_click(self.window, object()))
        self.assertEqual(self.window.model.tasks[0]["title"], "更名后")
        self.assertIsNone(self.window._editing)

    def test_clicking_input_does_not_commit_inline_edit(self):
        field = self.editor()
        field.set_text("编辑中")
        with patch("pomodoro.app.Gtk.get_event_widget", return_value=self.window.entry):
            self.window.on_background_click(self.window, object())
        self.assertIsNotNone(self.window._editing)
        self.window._finish_edit(cancel=True)

    def test_drop_reorders_and_keeps_same_selected_task(self):
        first, second, third = [t["id"] for t in self.window.model.tasks]
        handle = self.window.rows_box.get_children()[2].get_children()[1]
        context = object()
        with patch("pomodoro.app.Gtk.drag_get_source_widget", return_value=handle), \
             patch("pomodoro.app.Gtk.drag_finish") as finish, \
             patch("pomodoro.app.GLib.idle_add"):
            self.window._drop_task(self.window.rows_box.get_children()[0],
                                   context, 0, 0, SimpleNamespace(get_text=lambda: third),
                                   0, 0, first)
            finish.assert_called_once_with(context, True, False, 0)
        self.assertEqual([t["id"] for t in self.window.model.tasks], [third, first, second])
        self.assertEqual(self.window.model.current_id, first)

    def test_undo_toast_dismisses(self):
        self.window.remove_task(self.window.model.tasks[-1]["id"])
        self.assertTrue(self.window.undo_bar.get_visible())
        self.window._dismiss_undo()
        self.assertFalse(self.window.undo_bar.get_visible())
        self.assertIsNone(self.window._deleted_task)
