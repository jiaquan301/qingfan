"""Regression tests for the shape-aware floating focus clock."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from pomodoro.core import Model


class FloatingPreferencesTests(unittest.TestCase):
    def test_opacity_is_bounded_and_persisted(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / 'state.json'
            model = Model()
            self.assertEqual(model.display, {'opacity': 0.90, 'pinned': True})
            model.set_opacity(0.42)
            self.assertEqual(model.display['opacity'], 0.70)
            model.set_opacity(1.30)
            self.assertEqual(model.display['opacity'], 1.00)
            model.set_opacity(0.85)
            model.display['pinned'] = False
            model.save(dest)
            reloaded = Model.load(dest)
            self.assertAlmostEqual(reloaded.display['opacity'], 0.85)
            self.assertFalse(reloaded.display['pinned'])

    def test_corrupt_display_settings_do_not_bypass_clamp(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / 'state.json'
            for display in ({'opacity': 0.01, 'pinned': 'false'},
                            {'opacity': float('inf'), 'pinned': 1},
                            ['bad'], None):
                with self.subTest(display=display):
                    dest.write_text(json.dumps({'display': display}))
                    restored = Model.load(dest)
                    self.assertGreaterEqual(restored.display['opacity'], 0.70)
                    self.assertLessEqual(restored.display['opacity'], 1.0)
                    self.assertIsInstance(restored.display['pinned'], bool)

    def test_default_focus_timing_is_unchanged(self):
        model = Model()
        self.assertEqual(model.settings, {'focus': 25, 'short': 5, 'long': 15})
        self.assertEqual(model.seconds(), 1500)
        self.assertEqual(model.completed_rounds, 0)


try:
    from test_gui import registered_test_application, HAS_DISPLAY, Gtk
    from pomodoro.app import Window
except (ImportError, ValueError):
    HAS_DISPLAY = False


@unittest.skipUnless(HAS_DISPLAY, 'GTK graphical display unavailable')
class FloatingOrbGuiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, XDG_DATA_HOME=self.temp.name)
        env.start()
        self.addCleanup(env.stop)
        self.app = registered_test_application()
        self.window = Window(self.app)
        self.addCleanup(self.window.destroy)
        self.window._set_mode(False)
        self.window.entry.set_text('写设计稿')
        self.window.add_task()

    def test_manager_is_a_separate_compact_surface(self):
        orb = self.window.orb_window
        self.assertFalse(orb.get_visible())
        self.assertTrue(self.window.get_visible())
        self.assertFalse(self.window.hero.get_visible())
        self.assertTrue(self.window.task_panel.get_visible())
        self.window._set_mode(True)
        self.assertTrue(orb.get_visible())
        self.assertFalse(self.window.get_visible())
        self.assertFalse(self.window.task_panel.get_visible())

    def test_orb_full_and_mini_are_real_separate_sizes(self):
        orb = self.window.orb_window
        self.assertFalse(orb.get_decorated())
        self.assertTrue(orb.get_app_paintable())
        self.window._set_mode(True)
        self.assertEqual(orb.canvas.get_size_request(), (326, 356))
        orb.set_mini(True)
        self.assertEqual(orb.canvas.get_size_request(), (100, 100))
        self.assertFalse(orb.controls.get_visible())
        orb.set_mini(False)
        self.assertEqual(orb.canvas.get_size_request(), (326, 356))
        self.assertTrue(orb.controls.get_visible())

    def test_mini_open_tasks_restores_manager(self):
        orb = self.window.orb_window
        self.window._set_mode(True)
        orb.set_mini(True)
        orb.open_tasks()
        self.assertFalse(orb.mini)
        self.assertFalse(orb.get_visible())
        self.assertTrue(self.window.get_visible())
        self.assertFalse(self.window.compact)

    def test_start_focus_hides_manager_and_keeps_one_timer(self):
        orb = self.window.orb_window
        self.window.toggle_timer()
        self.assertTrue(self.window.model.running())
        self.assertTrue(self.window.compact)
        self.assertTrue(orb.get_visible())
        self.assertFalse(self.window.get_visible())
        orb.set_mini(True)
        self.window.toggle_timer()
        self.assertFalse(self.window.model.running())
        self.assertTrue(orb.mini)
        self.assertTrue(orb.get_visible())

    def test_click_and_double_click_dont_schedule_duplicate_actions(self):
        orb = self.window.orb_window
        orb.set_mini(True)
        orb._press_at = (0, 0)
        event = SimpleNamespace(button=1)
        self.assertTrue(orb._on_canvas_release(orb.canvas, event))
        self.assertIsNotNone(orb._click_source)
        orb._cancel_click()
        self.assertIsNone(orb._click_source)
        self.assertTrue(orb.mini)
        self.assertFalse(orb._single_click())
        self.assertFalse(orb.mini)

    def test_opacity_changes_do_not_change_timer_state(self):
        self.window.toggle_timer()
        deadline = self.window.model.deadline
        self.window.model.set_opacity(0.75)
        self.window.orb_window.update()
        self.assertEqual(self.window.model.deadline, deadline)

    def test_settings_and_pin_are_persisted(self):
        self.window.toggle_pin()
        self.assertFalse(self.window.model.display['pinned'])
        self.assertFalse(self.window.orb_window.get_keep_above())
        self.window.model.save()
        self.assertFalse(Model.load().display['pinned'])
