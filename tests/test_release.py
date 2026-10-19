"""Regression cases for task dragging and untrusted on-disk state."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pomodoro.core import Model


class ReleaseTests(unittest.TestCase):
    def test_drag_moves_both_directions_and_keeps_timer(self):
        m = Model()
        for title in ('一', '二', '三', '四'):
            m.add(title)
        a, b, c, d = [t['id'] for t in m.tasks]
        m.current_id = b
        m.start_pause(now=100)
        self.assertTrue(m.reorder(a, c, after=True))
        self.assertEqual([t['id'] for t in m.tasks], [b, c, a, d])
        self.assertTrue(m.reorder(d, b))
        self.assertEqual([t['id'] for t in m.tasks], [d, b, c, a])
        self.assertEqual(m.current_id, b)
        self.assertEqual(m.deadline, 1600)
        self.assertFalse(m.reorder(b, b))
        self.assertFalse(m.reorder('external', b))
        self.assertFalse(m.reorder(b, 'missing'))
        self.assertFalse(m.reorder(d, b))

    def test_reordered_tasks_survive_restart(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            m = Model()
            for name in ('A', 'B', 'C'):
                m.add(name)
            m.reorder(m.tasks[2]['id'], m.tasks[0]['id'])
            m.save(path)
            self.assertEqual([t['title'] for t in Model.load(path).tasks], ['C', 'A', 'B'])

    def test_malformed_schema_never_crashes_startup(self):
        cases = [None, [], 7, {'settings': None}, {'settings': []},
                 {'tasks': None}, {'tasks': 1}, {'phase': []},
                 {'current_id': []}, {'remaining': float('inf')},
                 {'remaining': float('nan')}, {'completed_rounds': 'invalid'},
                 {'settings': {'focus': float('inf'), 'short': True}}]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            for payload in cases:
                with self.subTest(payload=payload):
                    path.write_text(json.dumps(payload))
                    m = Model.load(path)
                    self.assertGreaterEqual(m.seconds(), 0)
                    self.assertLessEqual(m.seconds(), 10800)
                    self.assertIn(m.phase, ('focus', 'short', 'long'))

    def test_bad_setting_does_not_erase_valid_tasks(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            payload = {'settings': {'focus': 'bad'}, 'tasks': [
                {'id': 'a', 'title': '保留任务'}, {'id': 'a', 'title': '重复 ID'},
                None, {'id': 'b', 'title': '  '}]}
            path.write_text(json.dumps(payload))
            m = Model.load(path)
            self.assertEqual([t['title'] for t in m.tasks], ['保留任务', '重复 ID'])
            self.assertEqual(len({t['id'] for t in m.tasks}), 2)
            m.save(path)
            backups = list(Path(temp).glob('state.recovery-*.json'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(json.loads(backups[0].read_text()), payload)

    def test_invalid_bytes_backed_up_before_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            path.write_bytes(b'\xffbroken')
            m = Model.load(path)
            m.add('新任务')
            m.save(path)
            self.assertEqual(next(Path(temp).glob('state.recovery-*.json')).read_bytes(), b'\xffbroken')
            self.assertEqual(Model.load(path).tasks[0]['title'], '新任务')

    def test_failed_atomic_write_preserves_old_state(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            m = Model()
            m.add('旧任务')
            m.save(path)
            before = path.read_bytes()
            m.add('新任务')
            with patch('pomodoro.core.os.replace', side_effect=OSError('disk error')):
                with self.assertRaises(OSError):
                    m.save(path)
            self.assertEqual(path.read_bytes(), before)

    def test_unreadable_state_is_not_treated_as_empty(self):
        with patch.object(Path, 'read_text', side_effect=PermissionError('denied')):
            with self.assertRaises(PermissionError):
                Model.load(Path('/irrelevant/state.json'))

    def test_setting_changes_keep_running_duration_across_restart(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            m = Model()
            m.start_pause()
            deadline = m.deadline
            m.update_settings({'focus': 1})
            self.assertEqual(m.deadline, deadline)
            self.assertEqual(m.phase_duration, 1500)
            m.save(path)
            loaded = Model.load(path)
            self.assertEqual(loaded.phase_duration, 1500)
            self.assertEqual(loaded.settings['focus'], 1)
            loaded.reset()
            self.assertEqual(loaded.phase_duration, 60)
            self.assertEqual(loaded.seconds(), 60)

    def test_idle_and_partly_paused_settings_policy(self):
        m = Model()
        m.update_settings({'focus': 10})
        self.assertEqual(m.seconds(), 600)
        self.assertEqual(m.phase_duration, 600)
        m.start_pause(now=100)
        m.start_pause(now=150)
        m.update_settings({'focus': 5})
        self.assertEqual(m.seconds(), 550)
        self.assertEqual(m.phase_duration, 600)
        m.reset()
        self.assertEqual(m.seconds(), 300)

    def test_legacy_state_without_phase_duration_still_loads(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            path.write_text(json.dumps({'phase': 'short', 'remaining': 200,
                                        'settings': {'short': 5}}))
            loaded = Model.load(path)
            self.assertEqual(loaded.phase_duration, 300)
            self.assertEqual(loaded.seconds(), 200)


    def test_completed_tasks_group_after_pending_and_restore_to_pending_end(self):
        model = Model()
        for title in ('A', 'B', 'C', 'D'):
            model.add(title)
        a, b, c, d = [task['id'] for task in model.tasks]
        self.assertTrue(model.complete(b, True))
        self.assertEqual([task['id'] for task in model.pending_tasks], [a, c, d])
        self.assertEqual([task['id'] for task in model.completed_tasks], [b])
        self.assertTrue(model.complete(b, False))
        self.assertEqual([task['id'] for task in model.pending_tasks], [a, c, d, b])
        self.assertFalse(model.completed_tasks)

    def test_reorder_is_limited_to_the_same_status_group(self):
        model = Model()
        for title in ('A', 'B', 'C'):
            model.add(title)
        a, b, c = [task['id'] for task in model.tasks]
        model.complete(b, True)
        self.assertFalse(model.reorder(a, b))
        self.assertTrue(model.reorder(c, a, after=True))
        self.assertEqual([task['id'] for task in model.pending_tasks], [a, c])
        self.assertEqual([task['id'] for task in model.completed_tasks], [b])

    def test_running_focus_cannot_be_switched_by_model_api(self):
        model = Model()
        model.add('A')
        model.add('B')
        a, b = [task['id'] for task in model.tasks]
        model.current_id = a
        model.start_pause(now=100)
        deadline = model.deadline
        self.assertFalse(model.select(b))
        self.assertEqual(model.current_id, a)
        self.assertEqual(model.deadline, deadline)
        self.assertTrue(model.running())
