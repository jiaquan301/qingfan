import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/crystal_clock.dart';

void main() {
  testWidgets('Cold UI opens clock and can start without task', (tester) async {
    final controller = QingfanController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 376,
          height: 408,
          child: CrystalClock(
            controller: controller,
            onTasks: () {},
            onSettings: () {},
            onMode: () {},
            onReset: () {},
            onDrag: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('自由专注'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clockCenter')));
    await tester.pump();
    expect(controller.engine.isRunning, isTrue);
    await tester.tap(find.byKey(const Key('clockCenter')));
    expect(controller.engine.isRunning, isFalse);
    controller.dispose();
  });

  testWidgets('Mini dial contains no big task or start button',
      (tester) async {
    final controller = QingfanController();
    controller.setMode(ClockMode.mini);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 104,
        height: 104,
        child: CrystalClock(
          controller: controller,
          onTasks: () {},
          onSettings: () {},
          onMode: () {},
          onReset: () {},
          onDrag: () {},
          onMore: () {},
        ),
      ),
    ));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('自由专注'), findsNothing);
    expect(find.byKey(const Key('clockCenter')), findsOneWidget);
    controller.dispose();
  });
}
