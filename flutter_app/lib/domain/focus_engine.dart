import 'dart:math' as math;

/// A monotonic clock keeps long focus intervals independent of frame timing.
abstract class MillisClock {
  int get elapsedMillis;
}

class SystemMillisClock implements MillisClock {
  SystemMillisClock() {
    _watch.start();
  }

  final Stopwatch _watch = Stopwatch();

  @override
  int get elapsedMillis => _watch.elapsedMilliseconds;
}

enum FocusPhase { focus, shortBreak, longBreak }
enum RunState { idle, running, paused }

/// Pure Dart domain object; no widget, plugin, background Timer or IO.
class FocusEngine {
  FocusEngine({
    MillisClock? clock,
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
  }) : _clock = clock ?? SystemMillisClock() {
    _remainingAtStart = phaseDurationMillis;
  }

  final MillisClock _clock;
  int focusMinutes;
  int shortBreakMinutes;
  int longBreakMinutes;
  int completedRounds = 0;
  FocusPhase phase = FocusPhase.focus;
  RunState runState = RunState.idle;

  int _remainingAtStart = 0;
  int _startedAt = 0;
  int _lastFinishedSession = -1;
  int _sessionSerial = 0;

  int get phaseDurationMillis {
    final minutes = switch (phase) {
      FocusPhase.focus => focusMinutes,
      FocusPhase.shortBreak => shortBreakMinutes,
      FocusPhase.longBreak => longBreakMinutes,
    };
    return minutes * 60000;
  }

  int get remainingMillis {
    if (runState != RunState.running) return _remainingAtStart;
    return math.max(0, _remainingAtStart - (_clock.elapsedMillis - _startedAt));
  }

  bool get isRunning => runState == RunState.running;
  bool get hasPartialFocus =>
      phase == FocusPhase.focus &&
      runState != RunState.running &&
      remainingMillis < phaseDurationMillis;

  /// Starts or pauses the current phase. Does not require a task.
  void toggle() {
    if (runState == RunState.running) {
      _remainingAtStart = remainingMillis;
      runState = RunState.paused;
    } else {
      _startedAt = _clock.elapsedMillis;
      runState = RunState.running;
    }
  }

  /// Returns true ONLY for a newly finished focus period.
  ///
  /// Repeated tick calls at the same time cannot double-credit a round.
  bool tick() {
    if (runState != RunState.running || remainingMillis > 0) return false;
    if (_lastFinishedSession == _sessionSerial) return false;
    _lastFinishedSession = _sessionSerial;
    final didFinishFocus = phase == FocusPhase.focus;
    if (didFinishFocus) {
      completedRounds++;
      phase = completedRounds % 4 == 0
          ? FocusPhase.longBreak
          : FocusPhase.shortBreak;
    } else {
      phase = FocusPhase.focus;
    }
    _remainingAtStart = phaseDurationMillis;
    runState = RunState.idle;
    _sessionSerial++;
    return didFinishFocus;
  }

  /// Abandons the current break and prepares a fresh focus period.
  /// Completed rounds and per-task credits are never changed by skipping.
  void skipBreak() {
    if (phase == FocusPhase.focus) return;
    phase = FocusPhase.focus;
    _remainingAtStart = phaseDurationMillis;
    runState = RunState.idle;
    _sessionSerial++;
  }

  /// Restarting a round always returns to focus, even during a break.
  void reset() {
    phase = FocusPhase.focus;
    _remainingAtStart = phaseDurationMillis;
    runState = RunState.idle;
    _sessionSerial++;
  }

  void configure({int? focus, int? shortBreak, int? longBreak}) {
    if (focus != null) focusMinutes = focus.clamp(1, 180);
    if (shortBreak != null) shortBreakMinutes = shortBreak.clamp(1, 180);
    if (longBreak != null) longBreakMinutes = longBreak.clamp(1, 180);
    if (runState == RunState.idle) _remainingAtStart = phaseDurationMillis;
  }

  /// Restored sessions never silently auto-start; elapsed work is not invented.
  void restore(Map<String, dynamic> json) {
    focusMinutes = _minutes(json['focusMinutes'], 25);
    shortBreakMinutes = _minutes(json['shortBreakMinutes'], 5);
    longBreakMinutes = _minutes(json['longBreakMinutes'], 15);
    completedRounds = math.max(0, _integer(json['completedRounds'], 0));
    phase = FocusPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => FocusPhase.focus,
    );
    // A break is optional. Never strand a newly opened app in the old
    // break countdown; preserve completed rounds but offer fresh focus.
    // Interrupted focus, unlike interrupted break, remains paused.
    if (phase != FocusPhase.focus) {
      phase = FocusPhase.focus;
      _remainingAtStart = phaseDurationMillis;
      runState = RunState.idle;
    } else {
      final remaining = _integer(json['remainingMillis'], phaseDurationMillis);
      _remainingAtStart = remaining.clamp(0, phaseDurationMillis);
      runState = _remainingAtStart < phaseDurationMillis
          ? RunState.paused
          : RunState.idle;
    }
    _sessionSerial++;
  }

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'completedRounds': completedRounds,
        'phase': phase.name,
        'runState': runState == RunState.running ? 'paused' : runState.name,
        'remainingMillis': remainingMillis,
      };

  static int _integer(Object? n, int fallback) =>
      n is int && n >= 0 ? n : fallback;

  static int _minutes(Object? value, int fallback) =>
      _integer(value, fallback).clamp(1, 180);
}
