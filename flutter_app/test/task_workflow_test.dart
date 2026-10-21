import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qingfan/main.dart' show QingfanApp;
import 'package:qingfan/infrastructure/window_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/infrastructure/local_store.dart';
import 'package:qingfan/presentation/task_drawer.dart';

void main() {
  test('Complete, undo, restore and delete are distinct from selecting', () {
    final c = QingfanController();
    addTearDown(c.dispose);
    c.addTask('A');
    c.addTask('B');
    final a = c.pending.first.id;
    final b = c.pending.last.id;
    expect(c.selectedTaskId, a);
    expect(c.completeTask(b), true);
    expect(c.selectedTaskId, a);
    expect(c.pending.length, 1);
    expect(c.completed.single.id, b);
    expect(c.undoTaskChange(), true);
    expect(c.pending.length, 2);
    expect(c.completed, isEmpty);
    expect(c.selectTask(b), true);
    expect(c.selectedTaskId, b);
    expect(c.deleteTask(b), true);
    expect(c.selectedTaskId, a);
    expect(c.undoTaskChange(), true);
    expect(c.selectedTaskId, b);
    expect(c.pending.map((e) => e.id).toList(), [a, b]);
  });

  test('Undo preserves newly added or edited unrelated tasks', () {
    final c = QingfanController();
    addTearDown(c.dispose);
    c.addTask('A');
    c.addTask('B');
    final b = c.pending.last.id;
    expect(c.deleteTask(b), true);
    c.addTask('C');
    final third = c.pending.last.id;
    c.renameTask(third, 'C edited');
    expect(c.undoTaskChange(), true);
    expect(c.pending.map((e) => e.title).toList(), ['A', 'B', 'C edited']);
    expect(c.undoTaskChange(), false);
  });

  test('Completed count survives selection changes and restore', () {
    final c = QingfanController();
    addTearDown(c.dispose);
    c.addTask('A');
    final task = c.pending.first;
    task.pomodoros = 4;
    expect(c.completeTask(task.id), true);
    expect(c.completed.single.pomodoros, 4);
    expect(c.completeTask(task.id), true);
    expect(c.pending.single.pomodoros, 4);
  });

  test('Fifty items keep a single ordered queue with keyboard movement', () {
    final c = QingfanController();
    addTearDown(c.dispose);
    for (var i = 0; i < 50; i++) {
      c.addTask('Task $i');
    }
    expect(c.pending.length, 50);
    final bottom = c.pending.last.id;
    c.moveTask(bottom, -1);
    expect(c.pending[48].id, bottom);
    expect(c.pending[49].title, 'Task 48');
    c.reorderTask(0, 49);
    expect(c.pending.last.title, 'Task 0');
    expect(c.pending.length, 50);
  });

  test('Local JSON state is saved and loaded without network', () async {
    final directory = await Directory.systemTemp.createTemp('qingfan-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(testDirectory: directory);
    final a = QingfanController(store: store);
    a.addTask('测试任务');
    a.setOpacity(.85);
    a.configureTimes(40, 8, 20);
    a.setAlwaysOnTop(true);
    await a.flush();
    a.dispose();
    final b = QingfanController(store: store);
    await b.load();
    expect(b.tasks.single.title, '测试任务');
    expect(b.glassOpacity, .85);
    expect(b.engine.focusMinutes, 40);
    expect(b.engine.shortBreakMinutes, 8);
    expect(b.engine.longBreakMinutes, 20);
    expect(b.alwaysOnTop, isTrue);
    b.dispose();
  });

  test('Corrupt local JSON is quarantined rather than silently erased', () async {
    final directory = await Directory.systemTemp.createTemp('qingfan-corrupt-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(testDirectory: directory);
    final source = File('${directory.path}${Platform.pathSeparator}qingfan_v2.json');
    await source.writeAsString('{broken json');
    expect(await store.load(), isNull);
    expect(await source.exists(), isFalse);
    final quarantined = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.broken-'));
    expect(quarantined.length, 1);
    expect(await quarantined.single.readAsString(), '{broken json');
  });

  testWidgets('Search expands matching completed tasks while normally collapsed',
      (tester) async {
    final c = QingfanController();
    c.addTask('待办工作');
    c.addTask('已经完成甲');
    expect(c.completeTask(c.pending.last.id), true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 450,
          height: 540,
          child: TaskDrawer(
            controller: c,
            onClose: () {},
            onStart: () {},
          ),
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('taskSearch')), '完成甲');
    await tester.pumpAndSettle();
    expect(find.text('已经完成甲'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Clock stays transparent while switching full, mini and panel modes', (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(
      QingfanApp(controller: c, bridge: DesktopWindowBridge()),
    );
    await tester.pump();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      Colors.transparent,
    );
    c.setMode(ClockMode.mini);
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      Colors.transparent,
    );

    c.openPanel(OpenPanel.tasks);
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      isNot(Colors.transparent),
    );

    c.closePanel();
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      Colors.transparent,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Full, mini, tasks and settings fit at 100/125/150/200% display scales',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scale in [1.0, 1.25, 1.5, 2.0]) {
      tester.view.devicePixelRatio = scale;
      tester.view.physicalSize = Size(376 * scale, 408 * scale);

      final c = QingfanController();
      for (var i = 0; i < 50; i++) {
        c.addTask('缩放验收任务 ${i + 1}');
      }

      await tester.pumpWidget(
        QingfanApp(controller: c, bridge: DesktopWindowBridge()),
      );
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'full clock at $scale');

      c.setMode(ClockMode.mini);
      tester.view.physicalSize = Size(104 * scale, 104 * scale);
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'mini clock at $scale');

      c.openPanel(OpenPanel.tasks);
      tester.view.physicalSize = Size(714 * scale, 510 * scale);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('taskScroll')), findsOneWidget);
      final action = find.byKey(const Key('drawerStartFocus'));
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(510));
      expect(tester.takeException(), isNull, reason: 'tasks at $scale');

      c.openPanel(OpenPanel.settings);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('durationInput2')), findsOneWidget);
      expect(find.byKey(const Key('glassOpacity')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'settings at $scale');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('Space typed inside task input must not toggle focus', (tester) async {
    final c = QingfanController();
    c.openPanel(OpenPanel.tasks);
    await tester.pumpWidget(
      QingfanApp(controller: c, bridge: DesktopWindowBridge()),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('newTask')));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(c.engine.isRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('0, 5, 20 and 50 tasks keep the primary action fixed and reachable',
      (tester) async {
    for (final count in [0, 5, 20, 50]) {
      final c = QingfanController();
      for (var i = 0; i < count; i++) {
        c.addTask('任务 $i');
      }
      var started = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 410,
            height: 510,
            child: TaskDrawer(
              controller: c,
              onClose: () {},
              onStart: () => started = true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('taskScroll')), findsOneWidget);
      final action = find.byKey(const Key('drawerStartFocus'));
      expect(action, findsOneWidget);
      final initialRect = tester.getRect(action);
      expect(initialRect.bottom, lessThanOrEqualTo(510));
      expect(initialRect.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);

      if (count == 50) {
        await tester.scrollUntilVisible(
          find.text('任务 49'),
          260,
          scrollable: find.descendant(
            of: find.byKey(const Key('taskScroll')),
            matching: find.byType(Scrollable),
          ).first,
        );
        await tester.pumpAndSettle();
        final afterScrollRect = tester.getRect(action);
        expect(afterScrollRect.top, initialRect.top);
        expect(afterScrollRect.bottom, initialRect.bottom);
        expect(find.text('任务 49'), findsOneWidget);
      }
      await tester.tap(action);
      expect(started, true);
      c.dispose();
    }
  });
}
