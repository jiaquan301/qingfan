import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/crystal_clock.dart';

void main() {
  testWidgets('Product entry is a single focus dial, without required tasks',
      (tester) async {
    final controller = QingfanController();
    addTearDown(controller.dispose);
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
    expect(controller.engine.isRunning, isTrue);
  });
}
