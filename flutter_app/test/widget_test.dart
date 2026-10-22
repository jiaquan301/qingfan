import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/crystal_clock.dart';

void main() {
  testWidgets('One 104px clock starts without a task', (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 104,
          height: 104,
          child: CrystalClock(
            controller: c,
            onTasks: () {},
            onDrag: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byKey(const Key('singleDial'))),
        const Size(104, 104));
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('自由专注'), findsNothing);
    await tester.tap(find.byKey(const Key('clockCenter')));
    expect(c.engine.isRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
