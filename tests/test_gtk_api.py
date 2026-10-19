"""Check layout calls against the installed GTK API without a display.

Gtk.Box.pack_start and Gtk.HeaderBar.pack_start have different signatures.
Parsing actual layout code against GI metadata catches this even on headless CI.
"""
import ast
import unittest
from pathlib import Path

try:
    from pomodoro.app import Gtk
except (ImportError, ValueError):
    Gtk = None


@unittest.skipUnless(Gtk is not None, 'System GTK 3 introspection required')
class GtkApiTests(unittest.TestCase):
    def test_container_pack_calls_match_gtk_signatures(self):
        source = Path(__file__).resolve().parents[1] / 'pomodoro/app.py'
        tree = ast.parse(source.read_text())
        attributes = {}
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assign) or not isinstance(node.value, ast.Call):
                continue
            call = node.value
            if isinstance(call.func, ast.Name) and call.func.id == 'style':
                call = call.args[0]
            if isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name) and call.func.value.id == 'Gtk':
                for target in node.targets:
                    if isinstance(target, ast.Attribute):
                        attributes[ast.unparse(target)] = getattr(Gtk, call.func.attr, None)
        checked = 0
        for function in (node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)):
            containers = attributes.copy()
            for node in ast.walk(function):
                if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
                    call = node.value
                    if isinstance(call.func, ast.Name) and call.func.id == 'style':
                        call = call.args[0]
                    if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Attribute):
                        continue
                    if not isinstance(call.func.value, ast.Name) or call.func.value.id != 'Gtk':
                        continue
                    cls = getattr(Gtk, call.func.attr, None)
                    if cls is not None:
                        for target in node.targets:
                            containers[ast.unparse(target)] = cls
            for node in ast.walk(function):
                if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
                    continue
                if node.func.attr not in ('pack_start', 'pack_end'):
                    continue
                receiver = ast.unparse(node.func.value)
                self.assertIn(receiver, containers, f'Cannot resolve {receiver} at line {node.lineno}')
                method = getattr(containers[receiver], node.func.attr)
                arguments = method.get_arguments()
                expected = {argument.get_name() for argument in arguments}
                with self.subTest(line=node.lineno, container=containers[receiver].__name__):
                    self.assertEqual(len(node.args) + len(node.keywords), len(expected))
                    self.assertTrue({kw.arg for kw in node.keywords} <= expected)
                checked += 1
        self.assertGreater(checked, 30, 'The check must cover the actual window layout')
