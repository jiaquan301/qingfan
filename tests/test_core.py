import tempfile
import unittest
from pathlib import Path
from pomodoro.core import Model

class CoreTests(unittest.TestCase):
    def test_tasks_and_persistence(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "state.json"
            m = Model(); m.add("  写商业计划书 "); m.add("审核材料")
            first = m.tasks[0]["id"]
            m.current_id = first
            m.move(first, 1)
            m.save(target)
            loaded = Model.load(target)
            self.assertEqual(loaded.current_title(), "写商业计划书")
            self.assertEqual(loaded.tasks[1]["id"], first)
            loaded.complete(first, True)
            self.assertIsNone(loaded.current_id)
            loaded.delete(first)
            self.assertEqual(len(loaded.tasks), 1)

    def test_timer_pause_and_transition(self):
        m = Model()
        m.start_pause(now=1000)
        self.assertEqual(m.seconds(now=1010), 1490)
        m.start_pause(now=1010)
        self.assertEqual(m.seconds(), 1490)
        m.start_pause(now=2000)
        self.assertIsNone(m.tick(now=3489))
        self.assertEqual(m.tick(now=3490), "focus")
        self.assertEqual(m.phase, "short")
        self.assertFalse(m.running())
        for _ in range(3):
            m.start_pause(now=4000)
            m.tick(now=4300)
            m.start_pause(now=5000)
            m.tick(now=6500)
        self.assertEqual(m.phase, "long")
        self.assertEqual(m.completed_rounds, 4)

    def test_invalid_state(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "bad.json"
            target.write_text("not json", encoding="utf-8")
            self.assertEqual(Model.load(target).phase, "focus")

if __name__ == "__main__":
    unittest.main()


class RegressionTests(unittest.TestCase):
    def test_fourth_focus_leads_to_long_break_then_focus(self):
        m = Model()
        for i in range(4):
            m.start_pause(now=i * 10000)
            self.assertEqual(m.tick(now=i * 10000 + 1500), 'focus')
            self.assertEqual(m.phase, 'long' if i == 3 else 'short')
            self.assertEqual(m.seconds(), 900 if i == 3 else 300)
            if i != 3:
                m.start_pause(now=i * 10000 + 1600)
                self.assertEqual(m.tick(now=i * 10000 + 1900), 'short')
                self.assertEqual(m.phase, 'focus')
        m.start_pause(now=45000)
        self.assertEqual(m.tick(now=45900), 'long')
        self.assertEqual(m.phase, 'focus')
        self.assertEqual(m.completed_rounds, 4)

    def test_running_timer_persists_as_paused_on_restart(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'state.json'
            m = Model()
            import time
            m.start_pause(now=time.time())
            m.save(dest)
            restored = Model.load(dest)
            self.assertFalse(restored.running())
            self.assertLessEqual(restored.seconds(), 1500)
            self.assertGreater(restored.seconds(), 0)

    def test_task_operations_and_empty_title(self):
        m = Model()
        m.add('   ')
        self.assertFalse(m.tasks)
        m.add('未来  第一步')
        m.add('第二步')
        task = m.tasks[0]['id']
        m.rename(task, '  完成第一步  ')
        self.assertEqual(m.tasks[0]['title'], '完成第一步')
        m.move(task, -1)
        self.assertEqual(m.tasks[0]['id'], task)
        m.current_id = task
        m.delete(task)
        self.assertIsNone(m.current_id)
        self.assertEqual(len(m.tasks), 1)

    def test_invalid_settings_cannot_crash_load(self):
        import json
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / 'state.json'
            file.write_text(json.dumps({'phase': 'invalid', 'settings': {'focus': 0, 'short': 99999, 'long': '5'}, 'tasks': []}))
            m = Model.load(file)
            self.assertEqual(m.phase, 'focus')
            self.assertEqual(m.settings, {'focus': 1, 'short': 180, 'long': 5})

    def test_saved_json_is_parseable_and_has_legacy_schema(self):
        import json
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / 'state.json'
            m = Model()
            m.add('计划')
            m.save(file)
            parsed = json.loads(file.read_text(encoding='utf-8'))
            self.assertEqual(set(parsed), {'tasks', 'current_id', 'phase', 'completed_rounds', 'remaining', 'settings', 'phase_duration'})
            self.assertFalse(file.with_name('state.json.tmp').exists())
