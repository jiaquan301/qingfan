import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/domain/focus_engine.dart';
import 'package:qingfan/application/qingfan_controller.dart';

class FakeClock implements MillisClock {
  int current = 0;
  @override
  int get elapsedMillis => current;
  void advance(int milliseconds) => current += milliseconds;
}

void main() {
  test('A focus session can start with no task', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock);
    final controller = QingfanController(engine: engine);
    expect(controller.selectedTaskId, isNull);
    controller.toggleFocus();
    expect(engine.isRunning, isTrue);
    clock.advance(1500000);
    expect(engine.tick(), isTrue);
    expect(engine.completedRounds, 1);
    expect(controller.tasks, isEmpty);
    controller.dispose();
  });

  test('Pausing preserves remaining time and completion is idempotent', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock);
    engine.toggle();
    clock.advance(1000);
    engine.toggle();
    expect(engine.remainingMillis, 1499000);
    clock.advance(50000);
    expect(engine.remainingMillis, 1499000);
    engine.toggle();
    clock.advance(1499000);
    expect(engine.tick(), isTrue);
    expect(engine.tick(), isFalse);
    expect(engine.completedRounds, 1);
  });

  test('Fourth completed focus goes to long break', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock);
    for (var i = 0; i < 4; i++) {
      expect(engine.phase, FocusPhase.focus);
      engine.toggle();
      clock.advance(1500000);
      expect(engine.tick(), isTrue);
      if (i < 3) {
        expect(engine.phase, FocusPhase.shortBreak);
        engine.toggle();
        clock.advance(300000);
        expect(engine.tick(), isFalse);
      }
    }
    expect(engine.phase, FocusPhase.longBreak);
    expect(engine.completedRounds, 4);
  });

  test('Restored running timer is paused, never auto-completed', () {
    final clock = FakeClock();
    final model = FocusEngine(clock: clock);
    model.restore({
      'focusMinutes': 25,
      'shortBreakMinutes': 5,
      'longBreakMinutes': 15,
      'phase': 'focus',
      'runState': 'running',
      'remainingMillis': 1120000,
      'completedRounds': 1,
    });
    expect(model.isRunning, isFalse);
    expect(model.runState, RunState.paused);
    expect(model.remainingMillis, 1120000);
    clock.advance(100000);
    expect(model.tick(), isFalse);
  });

  test('Skipping a short break starts fresh focus without adding a credit', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock);
    engine.toggle();
    clock.advance(25 * 60000);
    expect(engine.tick(), isTrue);
    expect(engine.phase, FocusPhase.shortBreak);
    expect(engine.completedRounds, 1);

    engine.toggle(); // Partway through the break.
    clock.advance(18000);
    engine.skipBreak();
    expect(engine.phase, FocusPhase.focus);
    expect(engine.runState, RunState.idle);
    expect(engine.remainingMillis, 25 * 60000);
    expect(engine.completedRounds, 1);
    expect(engine.tick(), isFalse);
    engine.toggle();
    expect(engine.isRunning, isTrue);
  });

  test('Reset while resting returns to focus, including long breaks', () {
    final engine = FocusEngine(clock: FakeClock());
    engine.restore({
      'phase': 'longBreak',
      'completedRounds': 4,
      'remainingMillis': 820000,
      'runState': 'paused',
    });
    // Reopening an interrupted long break starts at fresh focus.
    expect(engine.phase, FocusPhase.focus);
    expect(engine.completedRounds, 4);
    engine.toggle();
    engine.reset();
    expect(engine.phase, FocusPhase.focus);
    expect(engine.runState, RunState.idle);
    expect(engine.remainingMillis, engine.phaseDurationMillis);
    engine.skipBreak(); // No-op when already focusing.
    expect(engine.completedRounds, 4);
  });

  test('Restored break is never resumed from stale remaining time', () {
    for (final phase in ['shortBreak', 'longBreak']) {
      for (final state in ['running', 'paused', 'idle']) {
        final engine = FocusEngine(clock: FakeClock());
        engine.restore({
          'phase': phase,
          'runState': state,
          'remainingMillis': 23000,
          'completedRounds': 5,
          'focusMinutes': 40,
          'shortBreakMinutes': 7,
          'longBreakMinutes': 20,
        });
        expect(engine.phase, FocusPhase.focus);
        expect(engine.runState, RunState.idle);
        expect(engine.remainingMillis, 40 * 60000);
        expect(engine.completedRounds, 5);
      }
    }
  });

  test('Break expiry transitions to focus but never credits a new round', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock, focusMinutes: 1, shortBreakMinutes: 1);
    engine.toggle();
    clock.advance(60000);
    expect(engine.tick(), isTrue);
    expect(engine.completedRounds, 1);
    engine.toggle();
    clock.advance(60000);
    expect(engine.tick(), isFalse);
    expect(engine.phase, FocusPhase.focus);
    expect(engine.runState, RunState.idle);
    expect(engine.completedRounds, 1);
    expect(engine.remainingMillis, 60000);
  });

  test('Task start during break moves directly to running focus', () {
    final clock = FakeClock();
    final engine = FocusEngine(clock: clock, focusMinutes: 1);
    final c = QingfanController(engine: engine);
    c.addTask('旧任务');
    c.addTask('新任务');
    c.startFocus();
    clock.advance(60000);
    expect(engine.tick(), isTrue);
    expect(engine.phase, FocusPhase.shortBreak);
    expect(c.selectTask(c.pending.last.id), isTrue);
    c.startFocus();
    expect(engine.phase, FocusPhase.focus);
    expect(engine.isRunning, isTrue);
    expect(c.selectedTask?.title, '新任务');
    expect(engine.completedRounds, 1);
    c.dispose();
  });

  test('Reorder never loses completed tasks', () {
    final controller = QingfanController();
    controller.addTask('A');
    controller.addTask('B');
    controller.addTask('C');
    final a = controller.pending[0].id;
    final b = controller.pending[1].id;
    final c = controller.pending[2].id;
    expect(controller.completeTask(b), isTrue);
    controller.reorderTask(1, 0);
    expect(controller.pending.map((t) => t.id).toList(), [c, a]);
    expect(controller.completed.single.id, b);
    controller.dispose();
  });

  test('Task selection is blocked during active focus', () {
    final controller = QingfanController();
    controller.addTask('A');
    controller.addTask('B');
    final first = controller.selectedTaskId;
    controller.toggleFocus();
    expect(controller.selectTask(controller.pending[1].id), isFalse);
    expect(controller.selectedTaskId, first);
    expect(controller.engine.isRunning, isTrue);
    controller.dispose();
  });

  test('Opacity is clamped to readable range', () {
    final controller = QingfanController();
    controller.setOpacity(.23);
    expect(controller.glassOpacity, .7);
    controller.setOpacity(4);
    expect(controller.glassOpacity, 1);
    controller.dispose();
  });
}
