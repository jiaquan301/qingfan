import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/application/qingfan_controller.dart';
import 'package:qingfan/presentation/settings_pane.dart';
import 'package:qingfan/presentation/q_dialogs.dart';
import 'package:qingfan/presentation/q_style.dart';

void main() {
  Widget settings(QingfanController c, {VoidCallback? onClose}) => MaterialApp(
        theme: QStyle.theme(),
        home: Scaffold(
          body: SizedBox(
            width: 410,
            height: 510,
            child: SettingsPane(
              controller: c,
              onClose: onClose ?? () {},
            ),
          ),
        ),
      );

  testWidgets('Settings are compact and contain no duplicate pin or save button',
      (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(settings(c));
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.byKey(const Key('durationInput0')), findsOneWidget);
    expect(find.byKey(const Key('durationInput1')), findsOneWidget);
    expect(find.byKey(const Key('durationInput2')), findsOneWidget);
    expect(find.byKey(const Key('glassOpacity')), findsOneWidget);
    expect(find.text('始终置顶'), findsNothing);
    expect(find.text('保存并返回时钟'), findsNothing);
    expect(find.byKey(const Key('durationPlus0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Duration steppers and typed numbers autosave without submit button',
      (tester) async {
    final c = QingfanController();
    var closes = 0;
    await tester.pumpWidget(settings(c, onClose: () => closes++));
    expect(c.engine.focusMinutes, 25);
    await tester.tap(find.byKey(const Key('durationPlus0')));
    await tester.pump();
    expect(c.engine.focusMinutes, 26);
    await tester.tap(find.byKey(const Key('durationMinus0')));
    await tester.pump();
    expect(c.engine.focusMinutes, 25);

    await tester.enterText(find.byKey(const Key('durationInput1')), '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.engine.shortBreakMinutes, 8);

    await tester.enterText(find.byKey(const Key('durationInput2')), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.engine.longBreakMinutes, 180);

    await tester.tap(find.byTooltip('返回时钟'));
    await tester.pump();
    expect(closes, 1);
    expect(c.engine.shortBreakMinutes, 8);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Opacity changes in real time and keeps the clock model active',
      (tester) async {
    final c = QingfanController();
    await tester.pumpWidget(settings(c));
    await tester.drag(find.byKey(const Key('glassOpacity')), const Offset(-50, 0));
    await tester.pump();
    expect(c.glassOpacity, lessThan(.9));
    expect(c.glassOpacity, greaterThanOrEqualTo(.7));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Settings remain usable at 100 125 150 200 percent desktop DPI',
      (tester) async {
    for (final scale in [1.0, 1.25, 1.5, 2.0]) {
      final c = QingfanController();
      await tester.pumpWidget(MaterialApp(
        theme: QStyle.theme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(714, 510),
            devicePixelRatio: scale,
          ),
          child: Scaffold(
            body: SizedBox(
              width: 410,
              height: 510,
              child: SettingsPane(controller: c, onClose: () {}),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('durationInput2')), findsOneWidget);
      expect(find.byKey(const Key('glassOpacity')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('Confirmation dialogs use shared porcelain layout, not AlertDialog',
      (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      theme: QStyle.theme(),
      home: Builder(builder: (context) {
        homeContext = context;
        return const SizedBox();
      }),
    ));
    var confirmed = false;
    final result = QDialogs.confirm(
      homeContext,
      title: '重置专注？',
      description: '未完成时间会清零。',
      action: '重置',
    ).then((v) => confirmed = v);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    await result;
    expect(confirmed, isTrue);
  });

  testWidgets('Rename dialog returns typed task title',
      (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      theme: QStyle.theme(),
      home: Builder(builder: (context) {
        homeContext = context;
        return const SizedBox();
      }),
    ));
    String? renamed;
    final future = QDialogs.rename(homeContext, current: '以前的任务')
        .then((value) => renamed = value);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.byKey(const Key('renameTaskInput')), '新的任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await future;
    expect(renamed, '新的任务');
  });
}
