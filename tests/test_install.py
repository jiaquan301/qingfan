"""Install and uninstall in an isolated HOME, preserving user data."""
import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from gi.repository import Gio
except ImportError:
    Gio = None

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(Gio is not None, 'System PyGObject required')
class InstallerTests(unittest.TestCase):
    def test_install_upgrade_and_uninstall_preserve_data(self):
        with tempfile.TemporaryDirectory(prefix='qingfan-test-') as temp:
            home = Path(temp) / 'home with spaces'
            data = Path(temp) / 'custom data'
            home.mkdir()
            state = data / 'qingfan/state.json'
            state.parent.mkdir(parents=True)
            state.write_text('{"tasks": []}')
            env = dict(os.environ, HOME=str(home), XDG_DATA_HOME=str(data))
            for _ in range(2):
                subprocess.run(['sh', str(ROOT / 'install.sh')], env=env, check=True, capture_output=True)
            desktop = data / 'applications/app.qingfan.Pomodoro.desktop'
            entry = Gio.DesktopAppInfo.new_from_filename(str(desktop))
            self.assertIsNotNone(entry)
            self.assertEqual(shlex.split(entry.get_commandline()), [str(home / '.local/share/qingfan-app/run.sh')])
            subprocess.run(['sh', str(ROOT / 'uninstall.sh')], env=env, check=True, capture_output=True)
            self.assertFalse(desktop.exists())
            self.assertFalse((home / '.local/share/qingfan-app').exists())
            self.assertEqual(state.read_text(), '{"tasks": []}')
