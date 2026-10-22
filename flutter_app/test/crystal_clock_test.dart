import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/domain/focus_engine.dart';
import 'package:qingfan/presentation/crystal_clock.dart';

class FakeClock implements MillisClock {
  int current = 0;
  @override
  int get elapsedMillis => current;
}

void main() {
  Widget dial(QingfanController c) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: CrystalClock(
          controller: c, onTasks: () {}, onDrag: () {}, onMore: () {},
        ),
      ),
    ),
  );

  testWidgets('Only a 104px dial, time and ring: no task name or state text',
      (tester) async {
    final c = QingfanController();
    c.addTask('这段任务名称绝不能出现在表盘上');
    await tester.pumpWidget(dial(c));
    expect(tester.getSize(find.byKey(const Key('singleDial'))),
        const Size(104, 104));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.textContaining('任务名称'), findsNothing);
    for (final word in ['专注', '休息', '正在专注', '短休息', '长休息']) {
      expect(find.text(word), findsNothing);
    }
    expect(find.byTooltip('任务清单'), findsNothing);
    await tester.tap(find.byKey(const Key('clockCenter')));
    await tester.pump();
    expect(c.engine.isRunning, true);
    await tester.tap(find.byKey(const Key('clockCenter')));
    await tester.pump();
    expect(c.engine.runState, RunState.paused);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Rest automatically runs with no pause/play or skip actions',
      (tester) async {
    final clock = FakeClock();
    final e = FocusEngine(clock: clock, focusMinutes: 1);
    final c = QingfanController(engine: e);
    c.startFocus();
    clock.current = 60000;
    expect(e.tick(), true);
    await tester.pumpWidget(dial(c));
    expect(find.text('05:00'), findsOneWidget);
    expect(find.byKey(const Key('skipBreakStart')), findsNothing);
    await tester.tap(find.byKey(const Key('clockCenter')));
    expect(e.phase, FocusPhase.rest);
    expect(e.runState, RunState.running);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Play/pause action uses standard media icons only on hover',
      (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(dial(c));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('singleDial'))));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('focusToggleIcon')));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
