import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/crystal_clock.dart';
import 'package:qingfan/infrastructure/window_bridge.dart';
import 'package:qingfan/main.dart' show QingfanApp;

void main() {
  testWidgets('Only two frequent actions appear on full dial; rare actions use menu',
      (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(
      QingfanApp(controller: c, bridge: DesktopWindowBridge()),
    );
    await tester.pump();
    expect(find.byTooltip('任务清单'), findsOneWidget);
    expect(find.byTooltip('迷你模式'), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('重置计时'), findsNothing);
    expect(find.byTooltip('更多：设置、重置'), findsOneWidget);

    await tester.tap(find.byTooltip('更多：设置、重置'));
    await tester.pumpAndSettle();
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('重新开始本轮'), findsOneWidget);
    expect(find.text('始终置顶'), findsOneWidget);
    await tester.tap(find.text('重新开始本轮'));
    await tester.pumpAndSettle();
    expect(c.engine.isRunning, isFalse);
    c.dispose();
  });

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
