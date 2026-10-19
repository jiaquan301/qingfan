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
        current_id = payload.get('current_id')
        if not isinstance(current_id, str) or current_id not in {t['id'] for t in tasks if not t['done']}:
            current_id = None
        return cls(tasks=tasks, current_id=current_id, phase=phase,
                   completed_rounds=number(payload.get('completed_rounds', 0), 0, 0, 1000000000, integer=True),
                   remaining=number(payload.get('remaining', settings[phase] * 60), settings[phase] * 60, 0, 180 * 60),
                   settings=settings,
                   phase_duration=number(payload.get('phase_duration', settings[phase] * 60), settings[phase] * 60, 60, 180 * 60),
                   _needs_backup=repaired)

    def save(self, path: Path | None = None):
        path = path or data_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        value = {"tasks": self.tasks, "current_id": self.current_id, "phase": self.phase,
                 "completed_rounds": self.completed_rounds, "remaining": self.seconds(),
                 "settings": self.settings, "phase_duration": self.phase_duration}
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

    def add(self, title: str):
        title = title.strip()
        if not title:
            return
        self.tasks.append({"id": uuid.uuid4().hex, "title": title[:120], "done": False, "pomodoros": 0})

    def rename(self, task_id: str, title: str):
        title = title.strip()
        if title:
            for task in self.tasks:
                if task["id"] == task_id:
                    task["title"] = title[:120]
                    break

    def complete(self, task_id: str, done: bool):
        for task in self.tasks:
            if task["id"] == task_id:
                task["done"] = done
        if done and self.current_id == task_id:
            self.current_id = None

    def delete(self, task_id: str):
        self.tasks = [t for t in self.tasks if t["id"] != task_id]
        if self.current_id == task_id:
            self.current_id = None

    def move(self, task_id: str, direction: int):
        idx = next((i for i, task in enumerate(self.tasks) if task["id"] == task_id), -1)
        to = idx + direction
        if idx >= 0 and 0 <= to < len(self.tasks):
            self.tasks[idx], self.tasks[to] = self.tasks[to], self.tasks[idx]

    def reorder(self, task_id: str, target_id: str, after: bool = False) -> bool:
        """Move a task before/after a target without changing the current timer."""
        if task_id == target_id:
            return False
        source = next((t for t in self.tasks if t['id'] == task_id), None)
        if source is None or not any(t['id'] == target_id for t in self.tasks):
            return False
        original = [t['id'] for t in self.tasks]
        self.tasks.remove(source)
        target = next(i for i, t in enumerate(self.tasks) if t['id'] == target_id)
        self.tasks.insert(target + int(after), source)
        return original != [t['id'] for t in self.tasks]

    def select(self, task_id: str | None) -> bool:
        """Select exactly one task. Switching abandons an unfinished focus.

        Rest intervals remain untouched. Selection never starts the timer:
        the main start/pause control is the only timer trigger.
        """
        if task_id is not None and not any(task['id'] == task_id for task in self.tasks):
            return False
        if self.current_id == task_id:
            return False
        if self.phase == 'focus':
            self.reset()
        self.current_id = task_id
        return True

    def current_title(self):
        return next((task["title"] for task in self.tasks if task["id"] == self.current_id), "选择一个任务，开始专注")
