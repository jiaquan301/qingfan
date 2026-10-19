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

    def test_checkbox_means_complete_and_title_selects_current_task(self):
        first, second = (task["id"] for task in self.window.model.tasks[:2])
        self.assertEqual(self.window.model.current_id, first)
        first_row, second_row = self.window.rows_box.get_children()[:2]
        first_check, second_check = first_row.get_children()[0], second_row.get_children()[0]
        self.assertIsInstance(first_check, Gtk.CheckButton)
        self.assertTrue(first_check.get_active())
        self.assertFalse(second_check.get_active())

        second_stack = next(child for child in second_row.get_children() if isinstance(child, Gtk.Stack))
        second_stack.get_child_by_name('title').clicked()
        self.assertEqual(self.window.model.current_id, second)
        self.assertFalse(next(task for task in self.window.model.tasks if task['id'] == second)['done'])
        refreshed_rows = self.window.rows_box.get_children()
        self.assertTrue(refreshed_rows[1].get_style_context().has_class('is-current'))
        self.assertFalse(refreshed_rows[0].get_children()[0].get_active())
        self.assertFalse(refreshed_rows[1].get_children()[0].get_active())

        refreshed_rows[0].get_children()[0].set_active(True)
        self.assertTrue(next(task for task in self.window.model.tasks if task['id'] == first)['done'])
        self.assertEqual(self.window.model.current_id, second)
        self.assertEqual(len(self.window.model.completed_tasks), 1)

    def test_running_focus_prevents_task_switch_but_keeps_other_task_completable(self):
        current_id = self.window.model.current_id
        self.window.toggle_timer()
        self.window._set_mode(False)
        second_row = self.window.rows_box.get_children()[1]
        check = second_row.get_children()[0]
        stack = next(child for child in second_row.get_children() if isinstance(child, Gtk.Stack))
        self.assertTrue(check.get_sensitive(), 'non-current tasks may still be completed')
        stack.get_child_by_name('title').clicked()
        self.assertEqual(self.window.model.current_id, current_id)
        self.assertTrue(self.window.model.running())
        self.assertIn('请先暂停', self.window.status_label.get_text())

    def test_switch_task_confirms_before_discarding_partial_focus(self):
        self.window.model.start_pause(now=100)
        self.window.model.start_pause(now=200)
        self.assertEqual(self.window.model.seconds(), 1400)
        with patch.object(self.window, '_confirm_action', return_value=False) as confirm:
            self.window.select_task(self.window.model.tasks[1]["id"])
        confirm.assert_called_once()
        self.assertEqual(self.window.model.current_id, self.window.model.tasks[0]['id'])
        self.assertEqual(self.window.model.seconds(), 1400)

        with patch.object(self.window, '_confirm_action', return_value=True):
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
        handle = next(child for child in self.window.rows_box.get_children()[2].get_children()
                      if getattr(child, '_qingfan_task_id', None) is not None)
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
    def test_completed_tasks_are_collapsed_and_can_be_restored(self):
        first_id = self.window.model.pending_tasks[0]['id']
        self.window.complete_task(first_id, True)
        self.assertEqual(len(self.window.model.completed_tasks), 1)
        self.assertEqual(len(self.window.model.pending_tasks), 2)
        self.assertFalse(self.window.completed_rows_box.get_visible())
        self.assertTrue(self.window.completed_toggle.get_visible())

        self.window.completed_toggle.clicked()
        self.assertTrue(self.window.completed_rows_box.get_visible())
        completed_row = self.window.completed_rows_box.get_children()[0]
        check = completed_row.get_children()[0]
        self.assertTrue(check.get_active())
        check.set_active(False)
        self.assertEqual(len(self.window.model.completed_tasks), 0)
        self.assertEqual(self.window.model.pending_tasks[-1]['id'], first_id)

    def test_current_task_completion_does_not_stop_a_running_focus(self):
        current_id = self.window.model.current_id
        self.window.toggle_timer()
        before = self.window.model.deadline
        self.window.complete_task(current_id, True)
        self.assertTrue(self.window.model.running())
        self.assertEqual(self.window.model.current_id, current_id)
        self.assertEqual(self.window.model.deadline, before)
        self.assertFalse(self.window.model.tasks[0]['done'])

    def test_undo_completion_restores_task_order_selection_and_partial_timer(self):
        ids = [task['id'] for task in self.window.model.pending_tasks]
        self.window.model.start_pause(now=100)
        self.window.model.start_pause(now=200)
        with patch.object(self.window, '_confirm_action', return_value=True):
            self.window.complete_task(ids[0], True)
        self.assertNotEqual(self.window.model.current_id, ids[0])
        self.assertEqual(self.window.model.seconds(), 1500)
        self.window.undo_delete()
        self.assertEqual([task['id'] for task in self.window.model.pending_tasks], ids)
        self.assertEqual(self.window.model.current_id, ids[0])
        self.assertEqual(self.window.model.seconds(), 1400)
        self.assertFalse(self.window.model.running())

    def test_long_task_list_scrolls_without_growing_window(self):
        for index in range(50):
            self.window.model.add(f'长清单任务 {index:02d}')
        self.window.refresh_tasks()
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        size = self.window.get_size()
        self.assertEqual(len(self.window.rows_box.get_children()), 53)
        adjustment = self.window.scroller.get_vadjustment()
        self.assertGreater(adjustment.get_upper(), adjustment.get_page_size())
        self.assertEqual(self.window.get_size(), size)

