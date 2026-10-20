import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/crystal_clock.dart';
import 'package:qingfan/presentation/task_drawer.dart';

Widget _clock(QingfanController c, VoidCallback onDrag, {bool mini = false}) {
  if (mini) c.setMode(ClockMode.mini);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: mini ? 104 : 376,
        height: mini ? 104 : 408,
        child: CrystalClock(
          controller: c,
          onTasks: () {},
          onSettings: () {},
          onMode: () {},
          onReset: () {},
          onDrag: onDrag,
          onMore: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Full clock ring and explicit handle initiate pointer dragging',
      (tester) async {
    final c = QingfanController();
    var drags = 0;
    await tester.pumpWidget(_clock(c, () => drags++));
    final ring = tester.getRect(find.byKey(const Key('clockDragSurface')));
    final start = Offset(ring.center.dx, ring.top + 28);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(35, 20));
    await tester.pump();
    await gesture.up();
    expect(drags, 1);
    final grip = tester.getCenter(find.byKey(const Key('fullDragHandle')));
    final next = await tester.startGesture(grip);
    await next.moveBy(const Offset(32, 12));
    await tester.pump();
    await next.up();
    expect(drags, 2);

    // A click in the central action toggles focus, NOT window dragging.
    await tester.tap(find.byKey(const Key('clockCenter')));
    expect(c.engine.isRunning, true);
    expect(drags, 2);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Mini clock retains accessible native drag region',
      (tester) async {
    final c = QingfanController();
    var drags = 0;
    await tester.pumpWidget(_clock(c, () => drags++, mini: true));
    final grip = tester.getCenter(find.byKey(const Key('miniDragHandle')));
    final gesture = await tester.startGesture(grip);
    await gesture.moveBy(const Offset(32, 12));
    await tester.pump();
    await gesture.up();
    expect(drags, 1);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Undo strip disappears after seven seconds, without SnackBar',
      (tester) async {
    final c = QingfanController();
    c.addTask('仍在专注');
    c.addTask('要删除');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 450,
          height: 540,
          child: TaskDrawer(controller: c, onClose: () {}, onStart: () {}),
        ),
      ),
    ));
    expect(c.deleteTask(c.pending.last.id), true);
    await tester.pump();
    expect(find.byKey(const Key('undoTaskBanner')), findsOneWidget);
    expect(find.text('任务已删除'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.byKey(const Key('undoTaskBanner')), findsNothing);
    expect(c.canUndo, false);

    c.addTask('第二项');
    expect(c.deleteTask(c.pending.last.id), true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('undoTaskAction')));
    await tester.pump();
    expect(c.canUndo, false);
    expect(c.pending.map((t) => t.title), contains('第二项'));
    expect(find.byKey(const Key('undoTaskBanner')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
