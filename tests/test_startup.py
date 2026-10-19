"""Activation failure handling is testable without starting a GTK display."""
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

try:
    from pomodoro.app import Application
    GTK_AVAILABLE = True
except (ImportError, ValueError):
    GTK_AVAILABLE = False


@unittest.skipUnless(GTK_AVAILABLE, 'System GTK 3 required')
class ActivationTests(unittest.TestCase):
    def test_initialization_error_shows_reason_and_quits(self):
        app = SimpleNamespace(get_active_window=lambda: None, quit=MagicMock(), startup_failed=False)
        with patch('pomodoro.app.Window', side_effect=TypeError('invalid GTK argument')), \
                patch('pomodoro.app.Gtk.MessageDialog') as dialog, \
                patch('pomodoro.app.traceback.print_exc') as log:
            Application.do_activate(app)
        self.assertTrue(app.startup_failed)
        app.quit.assert_called_once()
        log.assert_called_once()
        dialog.return_value.format_secondary_text.assert_called_once()
        self.assertIn('invalid GTK argument', dialog.return_value.format_secondary_text.call_args.args[0])
        dialog.return_value.run.assert_called_once()
        dialog.return_value.destroy.assert_called_once()

    def test_normal_activation_presents_initialized_window(self):
        app = SimpleNamespace(get_active_window=lambda: None, startup_failed=False)
        with patch('pomodoro.app.Window') as window:
            Application.do_activate(app)
            window.assert_called_once_with(app)
            window.return_value.present.assert_called_once()
        self.assertFalse(app.startup_failed)

    def test_gui_fixtures_use_distinct_application_ids(self):
        from test_gui import create_test_application
        first = create_test_application()
        second = create_test_application()
        self.assertNotEqual(first.get_application_id(), second.get_application_id())
        self.assertNotEqual(first.get_application_id(), 'app.qingfan.Pomodoro')
        self.assertNotEqual(second.get_application_id(), 'app.qingfan.Pomodoro')
