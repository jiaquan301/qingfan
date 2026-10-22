import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/focus_engine.dart';
import '../infrastructure/local_store.dart';

enum ClockMode { full, mini }
enum OpenPanel { none, tasks, settings }

class QingfanTask {
  QingfanTask({
    required this.id,
    required this.title,
    this.done = false,
    this.pomodoros = 0,
  });

  final String id;
  String title;
  bool done;
  int pomodoros;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'pomodoros': pomodoros,
      };

  static QingfanTask? parse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || id.isEmpty || title is! String ||
        title.trim().isEmpty) {
      return null;
    }
    return QingfanTask(
      id: id,
      title: title.trim().substring(0, math.min(title.trim().length, 120)),
      done: raw['done'] == true,
      pomodoros: raw['pomodoros'] is int
          ? math.max(0, raw['pomodoros'] as int)
          : 0,
    );
  }
}

class TaskUndo {
  TaskUndo({
    required this.before,
    required this.index,
    required this.currentBefore,
    required this.currentAfter,
    this.focusBefore,
  });
  final QingfanTask before;
  final int index;
  final String? currentBefore;
  final String? currentAfter;
  final Map<String, dynamic>? focusBefore;
}

class QingfanController extends ChangeNotifier {
  QingfanController({FocusEngine? engine, LocalStore? store})
      : engine = engine ?? FocusEngine(),
        _store = store {
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final phaseBefore = this.engine.phase;
      final stateBefore = this.engine.runState;
      final completed = this.engine.tick();
      // Break completion returns false (no focus credit), but still
      // changes the active phase and MUST repaint and save.
      final transitioned = phaseBefore != this.engine.phase ||
          stateBefore != this.engine.runState;
      if (completed && selectedTaskId != null) {
        for (final task in tasks) {
          if (task.id == selectedTaskId && !task.done) {
            task.pomodoros++;
            break;
          }
        }
      }
      if (transitioned) _scheduleSave();
      if (transitioned || this.engine.isRunning) notifyListeners();
    });
  }

  final FocusEngine engine;
  final LocalStore? _store;
  final List<QingfanTask> tasks = [];
  String? selectedTaskId;
  ClockMode mode = ClockMode.full;
  OpenPanel panel = OpenPanel.none;
  double glassOpacity = 0.90;
  bool alwaysOnTop = false;
  bool topmostCapabilityLimited = false;
  String? statusMessage;

  late final Timer _ticker;
  Timer? _saveDebounce;
  Future<void> _saveQueue = Future<void>.value();
  Timer? _undoTimer;
  TaskUndo? _undo;
  String? undoMessage;
  int _serial = 0;

  bool get canUndo => _undo != null;

  TaskUndo _snapshot(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    final item = tasks[index];
    return TaskUndo(
      before: QingfanTask(
        id: item.id, title: item.title, done: item.done,
        pomodoros: item.pomodoros,
      ),
      index: index,
      currentBefore: selectedTaskId,
      currentAfter: selectedTaskId,
      focusBefore: selectedTaskId == id && !engine.isRunning
          ? engine.toJson()
          : null,
    );
  }

  void _setUndo(TaskUndo previous, String message) {
    _undoTimer?.cancel();
    _undo = TaskUndo(
      before: previous.before, index: previous.index,
      currentBefore: previous.currentBefore,
      currentAfter: selectedTaskId,
      focusBefore: previous.focusBefore,
    );
    undoMessage = message;
    _undoTimer = Timer(const Duration(seconds: 7), () {
      _undo = null;
      undoMessage = null;
      notifyListeners();
    });
  }

  bool undoTaskChange() {
    final op = _undo;
    if (op == null) return false;
    _undoTimer?.cancel();
    _undo = null;
    undoMessage = null;
    // Inverse a single task without rolling back unrelated additions/edits.
    tasks.removeWhere((t) => t.id == op.before.id);
    final pendingCount = tasks.where((t) => !t.done).length;
    final insert = op.before.done
        ? math.max(pendingCount, math.min(op.index, tasks.length))
        : math.min(op.index, pendingCount);
    tasks.insert(insert, op.before);
    if (selectedTaskId == op.currentAfter && !engine.isRunning &&
        (op.currentBefore == null ||
            tasks.any((t) => t.id == op.currentBefore && !t.done))) {
      selectedTaskId = op.currentBefore;
      if (op.focusBefore != null) engine.restore(op.focusBefore!);
    }
    notifyListeners();
    _scheduleSave();
    return true;
  }

  List<QingfanTask> get pending => tasks.where((t) => !t.done).toList();
  List<QingfanTask> get completed => tasks.where((t) => t.done).toList();
  QingfanTask? get selectedTask {
    for (final task in tasks) {
      if (task.id == selectedTaskId && !task.done) return task;
    }
    return null;
  }

  String get taskTitle => selectedTask?.title ?? '自由专注';
  String get formattedTime {
    final total = (engine.remainingMillis / 1000).ceil();
    final mm = total ~/ 60;
    final ss = total % 60;
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  double get progress {
    final duration = engine.phaseDurationMillis;
    return duration <= 0 ? 0 : (1 - engine.remainingMillis / duration).clamp(0.0, 1.0);
  }

  String get phaseLabel => switch (engine.phase) {
        FocusPhase.focus => switch (engine.runState) {
            RunState.idle => '准备专注',
            RunState.running => '正在专注',
            RunState.paused => '已暂停',
          },
        FocusPhase.shortBreak => '短休息',
        FocusPhase.longBreak => '长休息',
      };

  void toggleFocus() {
    engine.toggle();
    notifyListeners();
    _scheduleSave();
  }

  /// Start/resume focus. From a break, the unfinished rest is discarded.
  void startFocus() {
    if (engine.phase != FocusPhase.focus) engine.skipBreak();
    if (!engine.isRunning) engine.toggle();
    notifyListeners();
    _scheduleSave();
  }

  /// A deliberate break skip returns to a fresh, idle focus interval.
  void skipBreak() {
    if (engine.phase == FocusPhase.focus) return;
    engine.skipBreak();
    notifyListeners();
    _scheduleSave();
  }

  void resetFocus() {
    engine.reset();
    notifyListeners();
    _scheduleSave();
  }

  void setMode(ClockMode target) {
    if (mode == target && panel == OpenPanel.none) return;
    mode = target;
    panel = OpenPanel.none;
    notifyListeners();
    _scheduleSave();
  }

  void openPanel(OpenPanel target) {
    if (target == OpenPanel.none) {
      closePanel();
      return;
    }
    mode = ClockMode.full;
    panel = target;
    notifyListeners();
  }

  void closePanel() {
    if (panel == OpenPanel.none) return;
    panel = OpenPanel.none;
    notifyListeners();
  }

  void setOpacity(double opacity) {
    glassOpacity = opacity.clamp(0.7, 1.0);
    notifyListeners();
    _scheduleSave();
  }

  void setAlwaysOnTop(bool on) {
    alwaysOnTop = on;
    notifyListeners();
    _scheduleSave();
  }

  void showStatus(String? text) {
    statusMessage = text;
    notifyListeners();
  }

  void addTask(String title) {
    final text = title.trim();
    if (text.isEmpty) return;
    final task = QingfanTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-${++_serial}',
      title: text.substring(0, math.min(text.length, 120)),
    );
    final firstCompleted = tasks.indexWhere((t) => t.done);
    tasks.insert(firstCompleted < 0 ? tasks.length : firstCompleted, task);
    selectedTaskId ??= task.id;
    notifyListeners();
    _scheduleSave();
  }

  /// Returns false if running; the UI must confirm abandoning partial work.
  bool selectTask(String id, {bool discardPartial = false}) {
    if (!tasks.any((t) => t.id == id && !t.done)) return false;
    if (selectedTaskId == id) return true;
    if (engine.phase == FocusPhase.focus && engine.isRunning) return false;
    if (engine.hasPartialFocus && !discardPartial) return false;
    if (engine.hasPartialFocus) engine.reset();
    selectedTaskId = id;
    notifyListeners();
    _scheduleSave();
    return true;
  }

  bool completeTask(String id, {bool discardPartial = false}) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    final task = tasks[index];
    final isCurrent = selectedTaskId == id;
    if (isCurrent && engine.phase == FocusPhase.focus && engine.isRunning) {
      return false;
    }
    if (isCurrent && engine.hasPartialFocus && !discardPartial) return false;
    final previous = _snapshot(id);
    if (isCurrent && engine.hasPartialFocus) engine.reset();
    task.done = !task.done;
    tasks.removeAt(index);
    if (task.done) {
      tasks.add(task);
      if (isCurrent) {
        final remaining = pending;
        selectedTaskId = remaining.isEmpty ? null : remaining[math.min(index, remaining.length - 1)].id;
      }
    } else {
      final firstCompleted = tasks.indexWhere((t) => t.done);
      tasks.insert(firstCompleted < 0 ? tasks.length : firstCompleted, task);
    }
    _setUndo(previous, task.done ? '任务已完成' : '任务已恢复');
    notifyListeners();
    _scheduleSave();
    return true;
  }

  void reorderTask(int oldIndex, int newIndex) {
    final pendingTasks = pending;
    if (oldIndex < 0 || oldIndex >= pendingTasks.length) return;
    final destination = math.max(0, math.min(newIndex, pendingTasks.length - 1));
    final task = pendingTasks.removeAt(oldIndex);
    pendingTasks.insert(destination, task);
    final completedTasks = completed;
    tasks
      ..clear()
      ..addAll(pendingTasks)
      ..addAll(completedTasks);
    notifyListeners();
    _scheduleSave();
  }

  void moveTask(String id, int delta) {
    final current = pending.indexWhere((task) => task.id == id);
    if (current < 0) return;
    final destination = current + delta;
    if (destination < 0 || destination >= pending.length) return;
    reorderTask(current, destination);
  }

  void renameTask(String id, String title) {
    final clean = title.trim();
    if (clean.isEmpty) return;
    for (final task in tasks) {
      if (task.id == id) {
        task.title = clean.substring(0, math.min(120, clean.length));
        notifyListeners();
        _scheduleSave();
        return;
      }
    }
  }

  bool deleteTask(String id, {bool discardPartial = false}) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    final isCurrent = selectedTaskId == id;
    if (isCurrent && engine.isRunning) return false;
    if (isCurrent && engine.hasPartialFocus && !discardPartial) return false;
    final previous = _snapshot(id);
    if (isCurrent && engine.hasPartialFocus) engine.reset();
    tasks.removeAt(index);
    if (isCurrent) {
      final remaining = pending;
      selectedTaskId = remaining.isEmpty
          ? null
          : remaining[math.min(index, remaining.length - 1)].id;
    }
    _setUndo(previous, '任务已删除');
    notifyListeners();
    _scheduleSave();
    return true;
  }

  void configureTimes(int focus, int shortBreak, int longBreak) {
    engine.configure(focus: focus, shortBreak: shortBreak, longBreak: longBreak);
    notifyListeners();
    _scheduleSave();
  }

  Future<void> load() async {
    final data = await _store?.load();
    if (data == null) return;
    engine.restore(Map<String, dynamic>.from(data['session'] is Map ? data['session'] as Map : {}));
    final settings = data['settings'];
    if (settings is Map) {
      final opacity = settings['glassOpacity'];
      if (opacity is num && opacity.isFinite) {
        glassOpacity = opacity.toDouble().clamp(0.7, 1.0);
      }
      alwaysOnTop = settings['alwaysOnTop'] == true;
      mode = settings['clockMode'] == 'mini' ? ClockMode.mini : ClockMode.full;
    }
    tasks.clear();
    final rawTasks = data['tasks'];
    if (rawTasks is List) {
      final ids = <String>{};
      for (final raw in rawTasks) {
        final task = QingfanTask.parse(raw);
        if (task != null && ids.add(task.id)) tasks.add(task);
      }
    }
    final previous = data['currentTaskId'];
    selectedTaskId = previous is String &&
            tasks.any((t) => t.id == previous && !t.done)
        ? previous
        : null;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'settings': {
          'glassOpacity': glassOpacity,
          'alwaysOnTop': alwaysOnTop,
          'clockMode': mode.name,
        },
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'currentTaskId': selectedTaskId,
        'session': engine.toJson(),
      };

  Future<void> _enqueueSave() {
    final store = _store;
    if (store == null) return Future<void>.value();
    // Capture the state NOW. All writes are serialized so async disk IO
    // cannot race over the same temporary file or regress to stale state.
    final snapshot = toJson();
    _saveQueue = _saveQueue.then((_) => store.save(snapshot)).catchError(
      (Object error, StackTrace trace) {
        statusMessage = '本地数据保存失败，请检查磁盘空间与目录权限';
        notifyListeners();
      },
    );
    return _saveQueue;
  }

  void _scheduleSave() {
    if (_store == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_enqueueSave());
    });
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    await _enqueueSave();
  }

  @override
  void dispose() {
    _ticker.cancel();
    _saveDebounce?.cancel();
    _undoTimer?.cancel();
    super.dispose();
  }
}
