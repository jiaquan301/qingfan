"""Pomodoro timer and durable task model; independent of the graphical toolkit."""
from __future__ import annotations
import json
import math
import shutil
import os
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_SETTINGS = {"focus": 25, "short": 5, "long": 15}
DEFAULT_DISPLAY = {"opacity": 0.90, "pinned": True}


def data_path() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "qingfan" / "state.json"


@dataclass
class Model:
    tasks: list[dict] = field(default_factory=list)
    current_id: str | None = None
    phase: str = "focus"
    completed_rounds: int = 0
    remaining: float = 25 * 60
    deadline: float | None = None
    settings: dict = field(default_factory=lambda: DEFAULT_SETTINGS.copy())
    display: dict = field(default_factory=lambda: DEFAULT_DISPLAY.copy())
    phase_duration: float = 25 * 60
    _needs_backup: bool = field(default=False, repr=False)

    @classmethod
    def load(cls, path: Path | None = None) -> "Model":
        path = path or data_path()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return cls()
        except (ValueError, UnicodeError):
            return cls(_needs_backup=True)
        except OSError:
            # Do not silently replace data we could not read.
            raise
        if not isinstance(payload, dict):
            return cls(_needs_backup=True)

        repaired = False

        def number(value, default, low, high, integer=False):
            nonlocal repaired
            try:
                if isinstance(value, bool):
                    raise ValueError('boolean is not a duration')
                result = float(value)
                if not math.isfinite(result):
                    raise ValueError('non-finite number')
                result = int(result) if integer else result
                bounded = max(low, min(high, result))
                repaired |= bounded != result
                return bounded
            except (ValueError, TypeError, OverflowError):
                repaired = True
                return default

        raw_settings = payload.get('settings', {})
        if not isinstance(raw_settings, dict):
            raw_settings = {}
            repaired = True
        settings = {key: number(raw_settings.get(key, value), value, 1, 180, integer=True)
                    for key, value in DEFAULT_SETTINGS.items()}
        raw_display = payload.get('display', {})
        if not isinstance(raw_display, dict):
            raw_display = {}
            repaired = True
        opacity = number(raw_display.get('opacity', 0.90), 0.90, 0.70, 1.00)
        # Keep a boolean as a boolean, never coerce strings to truthy.
        pinned = raw_display.get('pinned', True)
        if not isinstance(pinned, bool):
            pinned = True
            repaired = True
        display = {"opacity": opacity, "pinned": pinned}
        phase = payload.get('phase', 'focus')
        if not isinstance(phase, str) or phase not in DEFAULT_SETTINGS:
            phase = 'focus'
            repaired = True
        raw_tasks = payload.get('tasks', [])
        if not isinstance(raw_tasks, list):
            raw_tasks = []
            repaired = True
        tasks, ids = [], set()
        for task in raw_tasks:
            if not isinstance(task, dict) or not isinstance(task.get('title'), str) or not task['title'].strip():
                repaired = True
                continue
            tid = task.get('id')
            if not isinstance(tid, str) or not tid or tid in ids:
                tid = uuid.uuid4().hex
                repaired = True
            ids.add(tid)
            raw_count = task.get('pomodoros', 0)
            if (not isinstance(raw_count, int) or isinstance(raw_count, bool)
                    or not 0 <= raw_count <= 1000000000):
                raw_count = 0
                repaired = True
            tasks.append({'id': tid, 'title': task['title'].strip()[:120],
                          'done': bool(task.get('done', False)), 'pomodoros': raw_count})
        # Keep pending work together and completed work together on disk.
        # Relative order within each group is preserved.
        tasks = [task for task in tasks if not task['done']] + [task for task in tasks if task['done']]
        current_id = payload.get('current_id')
        if not isinstance(current_id, str) or current_id not in {t['id'] for t in tasks if not t['done']}:
            current_id = None
        return cls(tasks=tasks, current_id=current_id, phase=phase,
                   completed_rounds=number(payload.get('completed_rounds', 0), 0, 0, 1000000000, integer=True),
                   remaining=number(payload.get('remaining', settings[phase] * 60), settings[phase] * 60, 0, 180 * 60),
                   settings=settings, display=display,
                   phase_duration=number(payload.get('phase_duration', settings[phase] * 60), settings[phase] * 60, 60, 180 * 60),
                   _needs_backup=repaired)

    def save(self, path: Path | None = None):
        path = path or data_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        value = {"tasks": self.tasks, "current_id": self.current_id, "phase": self.phase,
                 "completed_rounds": self.completed_rounds, "remaining": self.seconds(),
                 "settings": self.settings, "display": self.display,
                 "phase_duration": self.phase_duration}
        if self._needs_backup and path.exists():
            backup = path.with_name(f'state.recovery-{time.time_ns()}.json')
            shutil.copy2(path, backup)
            self._needs_backup = False
        temp = path.with_name(path.name + ".tmp")
        with temp.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)

    def set_opacity(self, value: float):
        """Visible-body opacity. The time lettering and progress arc stay opaque."""
        self.display["opacity"] = max(0.70, min(1.00, float(value)))

    def seconds(self, now: float | None = None) -> float:
        if self.deadline is None:
            return max(0, self.remaining)
        return max(0, self.deadline - (time.time() if now is None else now))

    def running(self) -> bool:
        return self.deadline is not None

    def start_pause(self, now: float | None = None):
        now = time.time() if now is None else now
        if self.deadline is not None:
            self.remaining = max(0, self.deadline - now)
            self.deadline = None
        else:
            if self.remaining <= 0:
                self.phase_duration = self.settings[self.phase] * 60
                self.remaining = self.phase_duration
            self.deadline = now + self.remaining

    def reset(self):
        self.deadline = None
        self.phase_duration = self.settings[self.phase] * 60
        self.remaining = self.phase_duration

    def update_settings(self, settings: dict):
        untouched = not self.running() and abs(self.seconds() - self.phase_duration) < 0.01
        self.settings.update({key: max(1, min(180, int(settings.get(key, value))))
                              for key, value in self.settings.items()})
        if untouched:
            self.reset()

    def tick(self, now: float | None = None) -> str | None:
        now = time.time() if now is None else now
        if self.deadline is None or now < self.deadline:
            return None
        old_phase = self.phase
        self.deadline = None
        if old_phase == "focus":
            # Credit exactly one fully completed focus interval to the selected
            # task. A pause, reset or rest interval never earns a pomodoro.
            for task in self.tasks:
                if task['id'] == self.current_id:
                    task['pomodoros'] = task.get('pomodoros', 0) + 1
                    break
            self.completed_rounds += 1
            self.phase = "long" if self.completed_rounds % 4 == 0 else "short"
        else:
            self.phase = "focus"
        self.phase_duration = self.settings[self.phase] * 60
        self.remaining = self.phase_duration
        return old_phase  # require explicit start for every new phase

    @property
    def pending_tasks(self) -> list[dict]:
        """Tasks not marked complete, in the user's execution order."""
        return [task for task in self.tasks if not task['done']]

    @property
    def completed_tasks(self) -> list[dict]:
        """Completed tasks, in completion order."""
        return [task for task in self.tasks if task['done']]

    def _normalize_task_groups(self):
        """Keep pending tasks first and completed tasks after them."""
        self.tasks = self.pending_tasks + self.completed_tasks

    def add(self, title: str):
        title = title.strip()
        if not title:
            return
        task = {"id": uuid.uuid4().hex, "title": title[:120], "done": False, "pomodoros": 0}
        first_completed = next((i for i, item in enumerate(self.tasks) if item['done']), len(self.tasks))
        self.tasks.insert(first_completed, task)

    def rename(self, task_id: str, title: str):
        title = title.strip()
        if title:
            for task in self.tasks:
                if task["id"] == task_id:
                    task["title"] = title[:120]
                    break

    def complete(self, task_id: str, done: bool) -> bool:
        """Complete or restore a task while keeping each group internally ordered.

        Restored tasks are appended to the pending queue. The current task is
        cleared when completed; the UI decides whether to select the next one.
        """
        task = next((item for item in self.tasks if item['id'] == task_id), None)
        if task is None or task['done'] == bool(done):
            return False
        if done:
            # The most recently completed task goes to the end of the completed
            # section; restoring a task appends it to the end of pending work.
            self.tasks.remove(task)
            task['done'] = True
            self.tasks.append(task)
            if self.current_id == task_id:
                self.current_id = None
        else:
            task['done'] = False
        self._normalize_task_groups()
        return True

    def delete(self, task_id: str):
        self.tasks = [task for task in self.tasks if task['id'] != task_id]
        if self.current_id == task_id:
            self.current_id = None

    def move(self, task_id: str, direction: int):
        task = next((item for item in self.tasks if item['id'] == task_id), None)
        if task is None or task.get('done'):
            return
        group = self.pending_tasks
        idx = next((i for i, item in enumerate(group) if item['id'] == task_id), -1)
        target = idx + direction
        if idx < 0 or not 0 <= target < len(group):
            return
        group[idx], group[target] = group[target], group[idx]
        self.tasks = group + self.completed_tasks

    def reorder(self, task_id: str, target_id: str, after: bool = False) -> bool:
        """Reorder within the same status group without touching timer state."""
        if task_id == target_id:
            return False
        source = next((item for item in self.tasks if item['id'] == task_id), None)
        target = next((item for item in self.tasks if item['id'] == target_id), None)
        if source is None or target is None or source['done'] != target['done']:
            return False
        group = self.completed_tasks if source['done'] else self.pending_tasks
        original = [item['id'] for item in group]
        group.remove(source)
        target_index = next(i for i, item in enumerate(group) if item['id'] == target_id)
        group.insert(target_index + int(after), source)
        if original == [item['id'] for item in group]:
            return False
        self.tasks = (self.pending_tasks + group) if source['done'] else (group + self.completed_tasks)
        return True

    def select(self, task_id: str | None) -> bool:
        """Select one pending task; never switch away during a running focus."""
        if task_id is not None and not any(
                task['id'] == task_id and not task['done'] for task in self.tasks):
            return False
        if self.current_id == task_id:
            return False
        if self.phase == 'focus' and self.running():
            return False
        if self.phase == 'focus':
            self.reset()
        self.current_id = task_id
        return True

    def current_title(self):
        return next((task["title"] for task in self.tasks
                     if task["id"] == self.current_id and not task['done']),
                    "选择任务，开始专注")
