import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../application/qingfan_controller.dart';

/// One and only one native window. All UI modes are Flutter views of it.
class DesktopWindowBridge {
  static const fullSize = Size(376, 408);
  static const miniSize = Size(104, 104);
  static const panelSize = Size(768, 540);

  bool get likelyWayland =>
      Platform.isLinux &&
      Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';

  Size sizeFor(ClockMode mode, OpenPanel panel) {
    if (panel != OpenPanel.none) return panelSize;
    return mode == ClockMode.mini ? miniSize : fullSize;
  }

  Future<void> prepare() => windowManager.ensureInitialized();

  Future<void> showInitial(QingfanController controller) async {
    final options = WindowOptions(
      size: sizeFor(controller.mode, controller.panel),
      minimumSize: miniSize,
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      await applyTopmost(controller);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> setSurface(QingfanController controller) async {
    await windowManager.setSize(sizeFor(controller.mode, controller.panel));
    await applyTopmost(controller);
  }

  Future<void> applyTopmost(QingfanController controller) async {
    try {
      await windowManager.setAlwaysOnTop(controller.alwaysOnTop);
      if (likelyWayland && controller.alwaysOnTop) {
        controller.topmostCapabilityLimited = true;
      } else {
        controller.topmostCapabilityLimited = false;
      }
    } catch (_) {
      controller.topmostCapabilityLimited = controller.alwaysOnTop;
    }
  }

  Future<void> beginDrag() => windowManager.startDragging();
  Future<void> close() => windowManager.close();
}
