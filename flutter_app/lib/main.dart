import 'dart:async';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/qingfan_controller.dart';
import 'domain/focus_engine.dart';
import 'infrastructure/instance_guard.dart';
import 'infrastructure/local_store.dart';
import 'infrastructure/window_bridge.dart';
import 'presentation/crystal_clock.dart';
import 'presentation/task_drawer.dart';
import 'presentation/settings_pane.dart';
import 'presentation/q_style.dart';
import 'presentation/q_dialogs.dart';

final GlobalKey<_QingfanAppState> _nativeAppKey = GlobalKey<_QingfanAppState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final instanceGuard = InstanceGuard();
  if (!await instanceGuard.acquire()) {
    stdout.writeln('QINGFAN_ALREADY_RUNNING');
    if (Platform.isLinux &&
        Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() != 'wayland') {
      try {
        await Process.run('wmctrl', ['-a', '青番'])
            .timeout(const Duration(milliseconds: 700));
      } catch (_) {
        // Raising an existing X11 window is optional; single instance isn't.
      }
    }
    exit(0);
  }
  final controller = QingfanController(store: LocalStore());
  await controller.load();
  final bridge = DesktopWindowBridge();
  await bridge.prepare();
  // One native runner, one 104px dial, regardless of previous V2 mode.
  runApp(QingfanApp(
    key: _nativeAppKey,
    controller: controller,
    bridge: bridge,
  ));
  await bridge.showInitial(controller);
  if (args.contains('--native-smoke') ||
      Platform.environment['QINGFAN_NATIVE_SMOKE'] == '1') {
    await _nativeSmoke(controller, bridge);
  }
}

/// Inspects the actual running desktop window, not just its Flutter widgets.
/// Used under Xvfb + a real X11 window manager in GitHub Actions.
Future<void> _nativeSmoke(
  QingfanController controller, DesktopWindowBridge bridge,
) async {
  Future<void> check(String name, Size requested) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final measured = await windowManager.getSize();
    stdout.writeln('NATIVE_SMOKE_OBSERVED $name expected=${requested.width}x${requested.height} actual=${measured.width}x${measured.height}');
    if ((requested.width - measured.width).abs() > 4 ||
        (requested.height - measured.height).abs() > 4) {
      throw StateError('$name size expected $requested but was $measured');
    }
    stdout.writeln('NATIVE_SMOKE_SIZE $name: $measured');
    if (Platform.isLinux && Platform.environment['QINGFAN_NATIVE_CAPTURE'] == '1') {
      final windows = await Process.run('wmctrl', ['-lG']);
      final match = windows.stdout.toString().split('\n').firstWhere(
        (line) => line.contains('青番') || line.toLowerCase().contains('qingfan'),
        orElse: () => '',
      );
      if (match.isEmpty) throw StateError('No Qingfan X11 window to capture');
      final fields = match.trim().split(RegExp(r'\s+'));
      if (fields.length < 6) throw StateError('Invalid wmctrl geometry: $match');
      final windowId = fields[0];
      final width = int.parse(fields[4]);
      final height = int.parse(fields[5]);
      if (width < 80 || height < 80) {
        throw StateError('Invalid screenshot bounds: $match');
      }
      await Directory('native-shots').create(recursive: true);
      final output = 'native-shots/$name.png';
      // Capture the actual GTK window drawable by XID, not the Xvfb root
      // framebuffer. The root image can be uniform black when the headless
      // compositor has not copied child surfaces into the root pixmap.
      final rootOutput = 'native-shots/$name-root.png';
      double directEntropy = 0;
      double rootEntropy = 0;
      // Xvfb + software GTK can expose a correctly sized window before the
      // first Flutter frame has reached the drawable. Poll actual pixels,
      // with a hard timeout, instead of trusting a fixed sleep.
      for (var attempt = 0; attempt < 20; attempt++) {
        final screenshot = await Process.run(
          'import', ['-window', windowId, '-depth', '8', output],
        );
        if (screenshot.exitCode != 0 || !File(output).existsSync()) {
          throw StateError('Native screenshot $name failed: ${screenshot.stderr}');
        }
        final dimensions = await Process.run('identify', [
          '-format', '%w %h', output,
        ]);
        if (dimensions.exitCode != 0 ||
            dimensions.stdout.toString().trim() != '$width $height') {
          throw StateError('Native screenshot $name has unexpected dimensions: ${dimensions.stdout}');
        }
        final rootCapture = await Process.run('import', [
          '-window', 'root', '-crop',
          '${width}x$height+${int.parse(fields[2])}+${int.parse(fields[3])}',
          '-depth', '8', rootOutput,
        ]);
        if (rootCapture.exitCode != 0 || !File(rootOutput).existsSync()) {
          throw StateError('Native root screenshot $name failed: ${rootCapture.stderr}');
        }
        final direct = await Process.run('identify', [
          '-format', '%[entropy]', output,
        ]);
        final root = await Process.run('identify', [
          '-format', '%[entropy]', rootOutput,
        ]);
        directEntropy = double.tryParse(direct.stdout.toString().trim()) ?? 0;
        rootEntropy = double.tryParse(root.stdout.toString().trim()) ?? 0;
        if (directEntropy > 0.01 || rootEntropy > 0.01) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (directEntropy <= 0.01 && rootEntropy <= 0.01) {
        throw StateError('Native screenshot $name stayed blank after 5 seconds');
      }
      final bytes = await File(output).length();
      stdout.writeln('NATIVE_SCREENSHOT $name direct=$bytes bytes entropy=$directEntropy rootEntropy=$rootEntropy rootBytes=${await File(rootOutput).length()}');
    }
  }

  Future<void> checkTopmost(String surface) async {
    // The native plugin reports the actual topmost state on macOS and Windows.
    // Wayland compositors are allowed to restrict pinning.
    if (bridge.likelyWayland) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final reported = await windowManager.isAlwaysOnTop();
    stdout.writeln('NATIVE_TOPMOST_SURFACE $surface reported=$reported');
    if (!reported) {
      throw StateError('$surface lost the always-on-top state');
    }
  }

  try {
    await check('dial', bridge.effectiveDialWindowSize);
    if (Platform.isLinux &&
        Platform.environment['QINGFAN_NATIVE_DRAG'] == '1') {
      stdout.writeln('NATIVE_DRAG_READY dial');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    controller.setAlwaysOnTop(true);
    await bridge.applyTopmost(controller);
    await checkTopmost('dial');
    controller.openPanel(OpenPanel.menu);
    await bridge.setSurface(controller);
    await check('menu', DesktopWindowBridge.menuSize);
    await checkTopmost('menu');
    controller.openPanel(OpenPanel.tasks);
    await bridge.setSurface(controller);
    await check('tasks', DesktopWindowBridge.panelSize);
    await checkTopmost('tasks');
    for (var i = 0; i < 50; i++) {
      controller.addTask('界面验收任务 ${i + 1}');
    }
    await check('tasks_50', DesktopWindowBridge.panelSize);
    await checkTopmost('tasks_50');
    controller.openPanel(OpenPanel.settings);
    await bridge.setSurface(controller);
    await check('settings', DesktopWindowBridge.panelSize);
    await checkTopmost('settings');
    controller.closePanel();
    await bridge.setSurface(controller);
    await check('dial_return', bridge.effectiveDialWindowSize);
    await checkTopmost('dial_return');
    controller.setAlwaysOnTop(false);
    await bridge.applyTopmost(controller);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final clearedTop = await windowManager.isAlwaysOnTop();
    stdout.writeln('NATIVE_TOPMOST_RESET reported=$clearedTop');
    if (!bridge.likelyWayland && clearedTop) {
      throw StateError('Failed to clear always-on-top');
    }
    stdout.writeln('NATIVE_SMOKE_TOPMOST_ALL_SURFACES_PASS');
    stdout.writeln('NATIVE_SMOKE_PASS single 104px dial and panel');
    await controller.flush();
    await bridge.close();
  } catch (error, trace) {
    stderr.writeln('NATIVE_SMOKE_FAIL: $error\\n$trace');
    exitCode = 1;
    await bridge.close();
  }
}

class QingfanApp extends StatefulWidget {
  const QingfanApp({super.key, required this.controller, required this.bridge});

  final QingfanController controller;
  final DesktopWindowBridge bridge;

  @override
  State<QingfanApp> createState() => _QingfanAppState();
}

class _QingfanAppState extends State<QingfanApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Future<void> _windowSequence = Future<void>.value();

  QingfanController get c => widget.controller;

  void _surface(VoidCallback mutate) {
    mutate();
    // Only one native window may change size, and requests are serialized.
    _windowSequence = _windowSequence.then((_) async {
      await widget.bridge.setSurface(c);
    }).catchError((Object e) {
      c.showStatus('窗口切换受桌面环境限制：$e');
    });
  }

  void _showTasks() {
    _surface(() => c.openPanel(OpenPanel.tasks));
  }

  void _startFromTasks() {
    c.startFocus();
    _closePanel();
  }

  void _showSettings() {
    _surface(() => c.openPanel(OpenPanel.settings));
  }

  // A popup route cannot extend beyond a 104px native window. Expand the
  // same window to a compact operation pane instead of clipping the menu.
  void _showMoreMenu() {
    _surface(() => c.openPanel(OpenPanel.menu));
  }

  void _togglePin() {
    c.setAlwaysOnTop(!c.alwaysOnTop);
    unawaited(widget.bridge.applyTopmost(c));
    _closePanel();
  }

  Widget _menuPane() => Material(
    color: QStyle.canvas,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QPanelHeader(title: '更多', onClose: _closePanel),
          const SizedBox(height: 10),
          _menuAction(Icons.tune_rounded, '偏好设置', _showSettings),
          if (c.engine.phase == FocusPhase.focus)
            _menuAction(Icons.restart_alt_rounded, '重新开始本轮', () {
              unawaited(_confirmReset());
            }),
          _menuAction(
            c.alwaysOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            c.alwaysOnTop ? '取消置顶' : '始终置顶',
            _togglePin,
          ),
        ],
      ),
    ),
  );

  Widget _menuAction(IconData icon, String label, VoidCallback action) =>
      TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
        style: TextButton.styleFrom(
          foregroundColor: QStyle.jade,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      );

  void _closePanel() {
    _surface(c.closePanel);
  }

  bool get _textFieldHasFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  void _spaceShortcut() {
    // Typing a space in a task title or search field must never pause
    // or start the focus timer in the background.
    if (!_textFieldHasFocus) c.toggleFocus();
  }

  void _escapeShortcut() {
    // An editing field owns Escape first; only Escape from clock chrome
    // should close the whole task panel.
    if (_textFieldHasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      _closePanel();
    }
  }

  Future<void> _confirmReset() async {
    if (c.engine.phase == FocusPhase.rest) return;
    if (!c.engine.isRunning && !c.engine.hasPartialFocus) {
      c.resetFocus();
      if (c.panel == OpenPanel.menu) _closePanel();
      return;
    }
    final navigatorContext = _navigatorKey.currentState?.overlay?.context;
    if (navigatorContext == null) return;
    final accepted = await QDialogs.confirm(
      navigatorContext,
      title: '重新开始这一轮？',
      description: '未完成的专注时间将清零；已完成的番茄不会改变。',
      action: '重新开始',
    );
    if (accepted == true) {
      c.resetFocus();
      if (c.panel == OpenPanel.menu) _closePanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '青番',
      debugShowCheckedModeBanner: false,
      theme: QStyle.theme(),
      home: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.space): _spaceShortcut,
          // macOS uses Command; Windows and Linux use Ctrl.
          SingleActivator(LogicalKeyboardKey.keyL,
              control: !Platform.isMacOS, meta: Platform.isMacOS): _showTasks,
          SingleActivator(LogicalKeyboardKey.keyF,
              control: !Platform.isMacOS, meta: Platform.isMacOS): _showTasks,
          const SingleActivator(LogicalKeyboardKey.escape): _escapeShortcut,
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final open = c.panel != OpenPanel.none;
              return Scaffold(
                // Expanded task/settings workspaces are intentionally opaque.
                // A transparent GTK window behind them would show as a
                // large black rectangle on non-compositing Linux desktops.
                backgroundColor: open ? QStyle.canvas : Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!open)
                      CrystalClock(
                        controller: c,
                        onTasks: _showTasks,
                        onDrag: widget.bridge.beginDrag,
                        onMore: _showMoreMenu,
                      )
                    else
                      Row(
                        children: [
                          Container(
                            width: 112,
                            decoration: const BoxDecoration(
                              color: QStyle.panel,
                              border: Border(
                                right: BorderSide(
                                  color: QStyle.line, width: 1,
                                ),
                              ),
                            ),
                            child: CrystalClock(
                              controller: c,
                              onTasks: _closePanel,
                              onDrag: widget.bridge.beginDrag,
                              onMore: _showMoreMenu,
                            ),
                          ),
                          Expanded(
                            child: c.panel == OpenPanel.tasks
                                ? TaskDrawer(
                                    controller: c,
                                    onClose: _closePanel,
                                    onStart: _startFromTasks,
                                  )
                                : c.panel == OpenPanel.settings
                                    ? SettingsPane(
                                        controller: c,
                                        onClose: _closePanel,
                                      )
                                    : _menuPane(),
                          ),
                        ],
                      ),
                    if (c.statusMessage != null)
                      Positioned(
                        bottom: 5,
                        left: 8,
                        right: 8,
                        child: Material(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xDD284634),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              c.statusMessage!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(c.flush());
    super.dispose();
  }
}

