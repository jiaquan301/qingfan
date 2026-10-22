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

  test('Focus auto-starts one nonpausable rest, then stops at next focus', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1, restMinutes: 2);
    e.toggle();
    clock.advance(60000);
    expect(e.tick(), true);
    expect(e.completedRounds, 1);
    expect(e.phase, FocusPhase.rest);
    expect(e.runState, RunState.running);
    expect(e.remainingMillis, 120000);
    e.toggle(); // Nothing can pause rest.
    expect(e.runState, RunState.running);
    clock.advance(60000);
    expect(e.remainingMillis, 60000);
    clock.advance(60000);
    expect(e.tick(), false);
    expect(e.phase, FocusPhase.focus);
    expect(e.runState, RunState.idle);
    expect(e.remainingMillis, 60000);
    expect(e.tick(), false); // No duplicate credit.
    expect(e.completedRounds, 1);
  });

  test('Rest duration is the same on fourth and all subsequent rounds', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1, restMinutes: 3);
    for (var i = 1; i <= 5; i++) {
      e.startFocus();
      clock.advance(60000);
      expect(e.tick(), true);
      expect(e.phase, FocusPhase.rest);
      expect(e.remainingMillis, 180000);
      clock.advance(180000);
      expect(e.tick(), false);
      expect(e.phase, FocusPhase.focus);
      expect(e.runState, RunState.idle);
      expect(e.completedRounds, i);
    }
  });

  test('Task selection during rest does not interrupt rest; Start does', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1);
    final c = QingfanController(engine: e);
    c.addTask('A');
    c.addTask('B');
    c.startFocus();
    clock.advance(60000);
    expect(e.tick(), true);
    expect(c.selectTask(c.pending.last.id), true);
    expect(e.phase, FocusPhase.rest);
    expect(e.isRunning, true);
    c.startFocus();
    expect(e.phase, FocusPhase.focus);
    expect(e.isRunning, true);
    expect(e.completedRounds, 1);
    expect(c.selectedTask?.title, 'B');
    c.dispose();
  });

  test('Unfinished rest returns to fresh focus on restart, V2 migration works', () {
    for (final phase in ['rest', 'shortBreak', 'longBreak']) {
      final e = FocusEngine(clock: FakeClock());
      e.restore({
        'phase': phase, 'runState': 'running',
        'remainingMillis': 20000,
        'focusMinutes': 30, 'shortBreakMinutes': 7,
        'longBreakMinutes': 20, 'completedRounds': 4,
      });
      expect(e.restMinutes, 7);
      expect(e.phase, FocusPhase.focus);
      expect(e.runState, RunState.idle);
      expect(e.remainingMillis, 30 * 60000);
      expect(e.completedRounds, 4);
      expect(e.toJson().containsKey('longBreakMinutes'), false);
      expect(e.toJson().containsKey('shortBreakMinutes'), false);
    }
  });

  test('Overdue focus tick counts once and does not extend the past rest', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1, restMinutes: 1);
    e.startFocus();
    clock.advance(60000 + 45000);
    expect(e.tick(), true);
    expect(e.phase, FocusPhase.rest);
    expect(e.remainingMillis, 15000);
    clock.advance(20000);
    expect(e.tick(), false);
    expect(e.phase, FocusPhase.focus);
    expect(e.completedRounds, 1);
  });

  test('Rest never resets; focus reset clears incomplete work only', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1);
    e.toggle();
    clock.advance(60000);
    expect(e.tick(), true);
    e.reset();
    expect(e.phase, FocusPhase.rest);
    expect(e.runState, RunState.running);
    e.startFocus();
    expect(e.phase, FocusPhase.focus);
    expect(e.isRunning, true);
    expect(e.completedRounds, 1);
    e.reset();
    expect(e.phase, FocusPhase.focus);
    expect(e.runState, RunState.idle);
    expect(e.completedRounds, 1);
  });

  test('Editing durations during focus does not change remaining running time', () {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 25);
    e.startFocus();
    clock.advance(20000);
    final remaining = e.remainingMillis;
    e.configure(focus: 40, rest: 8);
    expect(e.remainingMillis, remaining);
    e.reset();
    expect(e.remainingMillis, 40 * 60000);
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
