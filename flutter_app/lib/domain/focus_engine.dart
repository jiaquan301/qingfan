import 'dart:math' as math;

/// Uses a monotonic clock so redraw frequency cannot change elapsed time.
abstract class MillisClock {
  int get elapsedMillis;
}

class SystemMillisClock implements MillisClock {
  SystemMillisClock() { _watch.start(); }
  final Stopwatch _watch = Stopwatch();
  @override
  int get elapsedMillis => _watch.elapsedMilliseconds;
}

enum FocusPhase { focus, rest }
enum RunState { idle, running, paused }

/// Two phases: focus is user-controlled; rest starts automatically and
/// cannot be paused. The next focus never starts without a user action.
class FocusEngine {
  FocusEngine({
    MillisClock? clock,
    this.focusMinutes = 25,
    this.restMinutes = 5,
  }) : _clock = clock ?? SystemMillisClock() {
    _intervalDurationMillis = focusMinutes * 60000;
    _remainingAtStart = _intervalDurationMillis;
  }

  final MillisClock _clock;
  int focusMinutes;
  int restMinutes;
  int completedRounds = 0;
  FocusPhase phase = FocusPhase.focus;
  RunState runState = RunState.idle;

  // Latched duration of the active interval. Preferences apply next time.
  int _intervalDurationMillis = 0;
  int _remainingAtStart = 0;
  int _startedAt = 0;
  int _sessionSerial = 0;
  int _lastFinishedSession = -1;

  int get phaseDurationMillis => _intervalDurationMillis;

  int get remainingMillis {
    if (runState != RunState.running) return _remainingAtStart;
    return math.max(0, _remainingAtStart - (_clock.elapsedMillis - _startedAt));
  }

  bool get isRunning => runState == RunState.running;
  bool get hasPartialFocus => phase == FocusPhase.focus &&
      runState != RunState.running && remainingMillis < phaseDurationMillis;

  /// Toggle only the focus interval. Rest is never pausible.
  void toggle() {
    if (phase != FocusPhase.focus) return;
    if (runState == RunState.running) {
      _remainingAtStart = remainingMillis;
      runState = RunState.paused;
    } else {
      _startedAt = _clock.elapsedMillis;
      runState = RunState.running;
    }
  }

  /// True only when one new focus interval has finished (for task credit).
  /// Carry wall-clock overshoot into rest so sleeping/late ticks cannot
  /// lengthen a rest; if both intervals elapsed, return to idle focus.
  bool tick() {
    if (runState != RunState.running || remainingMillis > 0) return false;
    if (_lastFinishedSession == _sessionSerial) return false;
    _lastFinishedSession = _sessionSerial;
    if (phase == FocusPhase.focus) {
      completedRounds++;
      final overdue = math.max(0, _clock.elapsedMillis - _startedAt -
          _remainingAtStart);
      phase = FocusPhase.rest;
      _intervalDurationMillis = restMinutes * 60000;
      _remainingAtStart = _intervalDurationMillis;
      _startedAt = _clock.elapsedMillis - overdue;
      runState = RunState.running;
      _sessionSerial++;
      if (remainingMillis == 0) _finishRest();
      return true;
    }
    _finishRest();
    return false;
  }

  void _finishRest() {
    phase = FocusPhase.focus;
    _intervalDurationMillis = focusMinutes * 60000;
    _remainingAtStart = _intervalDurationMillis;
    runState = RunState.idle;
    _sessionSerial++;
  }

  /// A new deliberate focus begins immediately, ending any ongoing rest.
  /// Selecting a task alone never calls this method.
  void startFocus() {
    if (phase == FocusPhase.rest) _finishRest();
    if (runState != RunState.running) toggle();
  }

  /// Restart current focus only; no restart or pause action during rest.
  void reset() {
    if (phase == FocusPhase.rest) return;
    _intervalDurationMillis = focusMinutes * 60000;
    _remainingAtStart = _intervalDurationMillis;
    runState = RunState.idle;
    _sessionSerial++;
  }

  /// Edits apply to the next interval, not the remainder of a running one.
  void configure({int? focus, int? rest}) {
    if (focus != null) focusMinutes = focus.clamp(1, 180);
    if (rest != null) restMinutes = rest.clamp(1, 180);
    if (runState == RunState.idle) {
      _intervalDurationMillis = focusMinutes * 60000;
      _remainingAtStart = _intervalDurationMillis;
    }
  }

  /// Backwards-compatible V2 migration: shortBreak maps to rest. Both old
  /// break phases reopen as fresh, idle focus. Incomplete focus resumes
  /// paused; completed rounds remain unchanged.
  void restore(Map<String, dynamic> json) {
    focusMinutes = _minutes(json['focusMinutes'], 25);
    restMinutes = _minutes(json['restMinutes'] ?? json['shortBreakMinutes'], 5);
    completedRounds = math.max(0, _integer(json['completedRounds'], 0));
    final wasRest = const ['rest', 'shortBreak', 'longBreak']
        .contains(json['phase']);
    phase = FocusPhase.focus;
    if (wasRest) {
      _intervalDurationMillis = focusMinutes * 60000;
      _remainingAtStart = _intervalDurationMillis;
      runState = RunState.idle;
    } else {
      // V2 files lack a latched interval. Keep any saved remaining time,
      // even if preferences were changed during the interrupted session.
      final savedRemaining = _integer(
          json['remainingMillis'], focusMinutes * 60000);
      final savedDuration = _integer(
          json['intervalDurationMillis'], focusMinutes * 60000);
      _intervalDurationMillis =
          math.max(savedRemaining, savedDuration.clamp(60000, 180 * 60000));
      _remainingAtStart = savedRemaining.clamp(0, _intervalDurationMillis);
      runState = _remainingAtStart < _intervalDurationMillis
          ? RunState.paused : RunState.idle;
    }
    _sessionSerial++;
  }

  Map<String, dynamic> toJson() => {
    'focusMinutes': focusMinutes,
    'restMinutes': restMinutes,
    'intervalDurationMillis': _intervalDurationMillis,
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
