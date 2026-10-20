import 'dart:async';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/qingfan_controller.dart';
import 'infrastructure/instance_guard.dart';
import 'infrastructure/local_store.dart';
import 'infrastructure/window_bridge.dart';
import 'presentation/crystal_clock.dart';
import 'presentation/task_drawer.dart';

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
  // A new app session opens in the full clock, irrespective of last size.
  // Only ONE GTK/native runner is ever created by this Flutter process.
  controller.setMode(ClockMode.full);
  runApp(QingfanApp(controller: controller, bridge: bridge));
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
      final bytes = await File(output).length();
      stdout.writeln('NATIVE_SCREENSHOT $name $output $bytes bytes');
    }
  }

  try {
    await check('full', DesktopWindowBridge.fullSize);
    controller.setMode(ClockMode.mini);
    await bridge.setSurface(controller);
    await check('mini', DesktopWindowBridge.miniSize);
    controller.setMode(ClockMode.full);
    await bridge.setSurface(controller);
    await check('full_return', DesktopWindowBridge.fullSize);
    controller.openPanel(OpenPanel.tasks);
    await bridge.setSurface(controller);
    await check('tasks', DesktopWindowBridge.panelSize);
    controller.closePanel();
    await bridge.setSurface(controller);
    await check('close_tasks', DesktopWindowBridge.fullSize);
    controller.setAlwaysOnTop(true);
    await bridge.applyTopmost(controller);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final reportedTop = await windowManager.isAlwaysOnTop();
    stdout.writeln('NATIVE_SMOKE_TOPMOST reported=$reportedTop');
    if (!bridge.likelyWayland && !reportedTop) {
      throw StateError('X11 or desktop runner refused always-on-top');
    }
    controller.setAlwaysOnTop(false);
    await bridge.applyTopmost(controller);
    stdout.writeln('NATIVE_SMOKE_PASS single-runner full mini panel topmost');
    await controller.flush();
    // Closing the native Flutter view invokes asynchronous GTK/engine
    // disposal. Do NOT call exit() during that process: it races engine
    // destruction and crashes Linux with FlutterEngineRemoveView.
    await bridge.close();
    await Future<void>.delayed(const Duration(seconds: 2));
    stdout.writeln('NATIVE_SMOKE_GRACEFUL_CLOSE_PASS');
    // The native GTK process should exit on its own when its only window
    // closes. If it stays running the external timeout correctly fails CI.
  } catch (error, trace) {
    stderr.writeln('NATIVE_SMOKE_FAIL: $error\n$trace');
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

  void _switchMode() {
    _surface(() => c.setMode(
        c.mode == ClockMode.mini ? ClockMode.full : ClockMode.mini));
  }

  void _showTasks() {
    _surface(() => c.openPanel(OpenPanel.tasks));
  }

  void _startFromTasks() {
    if (!c.engine.isRunning) c.toggleFocus();
    _closePanel();
  }

  void _showSettings() {
    _surface(() => c.openPanel(OpenPanel.settings));
  }

  void _closePanel() {
    _surface(c.closePanel);
  }

  Future<void> _confirmReset() async {
    if (!c.engine.isRunning && !c.engine.hasPartialFocus) {
      c.resetFocus();
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新开始这一轮？'),
        content: const Text('未完成的专注时间会清零，已经获得的番茄次数不会改变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (accepted == true) c.resetFocus();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青番',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F4),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF337259)),
        fontFamily: null,
      ),
      home: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.space): c.toggleFocus,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): _showTasks,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _showTasks,
          const SingleActivator(LogicalKeyboardKey.escape): _closePanel,
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final open = c.panel != OpenPanel.none;
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!open)
                      CrystalClock(
                        controller: c,
                        onTasks: _showTasks,
                        onSettings: _showSettings,
                        onMode: _switchMode,
                        onReset: _confirmReset,
                        onDrag: widget.bridge.beginDrag,
                        onMore: _switchMode,
                      )
                    else
                      Row(
                        children: [
                          SizedBox(
                            width: 330,
                            child: CrystalClock(
                              controller: c,
                              onTasks: _closePanel,
                              onSettings: _showSettings,
                              onMode: _closePanel,
                              onReset: _confirmReset,
                              onDrag: widget.bridge.beginDrag,
                              onMore: _closePanel,
                            ),
                          ),
                          Expanded(
                            child: c.panel == OpenPanel.tasks
                                ? TaskDrawer(
                                    controller: c,
                                    onClose: _closePanel,
                                    onStart: _startFromTasks,
                                  )
                                : _SettingsPane(
                                    controller: c,
                                    onClose: _closePanel,
                                    onPin: (value) async {
                                      c.setAlwaysOnTop(value);
                                      await widget.bridge.applyTopmost(c);
                                    },
                                  ),
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

class _SettingsPane extends StatefulWidget {
  const _SettingsPane({
    required this.controller,
    required this.onClose,
    required this.onPin,
  });

  final QingfanController controller;
  final VoidCallback onClose;
  final ValueChanged<bool> onPin;

  @override
  State<_SettingsPane> createState() => _SettingsPaneState();
}

class _SettingsPaneState extends State<_SettingsPane> {
  late double _focus = widget.controller.engine.focusMinutes.toDouble();
  late double _short = widget.controller.engine.shortBreakMinutes.toDouble();
  late double _long = widget.controller.engine.longBreakMinutes.toDouble();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Material(
      color: const Color(0xFFF9FCFA),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(children: [
          Row(children: [
            const Text('专注设置',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              tooltip: '关闭设置',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          const SizedBox(height: 10),
          _duration('专注时间', _focus, (v) => setState(() => _focus = v)),
          _duration('短休息', _short, (v) => setState(() => _short = v)),
          _duration('长休息', _long, (v) => setState(() => _long = v)),
          const Divider(),
          ListTile(
            title: const Text('玻璃背景透明度'),
            subtitle: Slider(
              value: c.glassOpacity,
              min: .7,
              max: 1,
              divisions: 6,
              label: '${(c.glassOpacity * 100).round()}%',
              onChanged: c.setOpacity,
            ),
            trailing: Text('${(c.glassOpacity * 100).round()}%'),
          ),
          SwitchListTile(
            title: const Text('始终置顶'),
            value: c.alwaysOnTop,
            onChanged: widget.onPin,
          ),
          if (c.topmostCapabilityLimited)
            const Text('当前 Linux Wayland 桌面可能不支持强制置顶。',
                style: TextStyle(color: Color(0xFF8A663B))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              c.configureTimes(_focus.round(), _short.round(), _long.round());
              widget.onClose();
            },
            child: const Text('保存并返回时钟'),
          ),
        ]),
      ),
    );
  }

  Widget _duration(String title, double value, ValueChanged<double> change) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title  ${value.round()} 分钟'),
        Slider(
          value: value,
          min: 1,
          max: 180,
          divisions: 179,
          onChanged: change,
        ),
      ]);
}
