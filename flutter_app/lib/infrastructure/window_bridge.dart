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
      await windowManager.setTitle('青番');
      // Flutter's default Linux runner starts at 1280x720. Do not freeze
      // that initial geometry before requesting the final 376x408 size.
      await windowManager.setResizable(true);
      await windowManager.setSize(sizeFor(controller.mode, controller.panel));
      await applyTopmost(controller);
      await windowManager.show();
      await windowManager.setSize(sizeFor(controller.mode, controller.panel));
      // window_manager 0.5.x on Linux reverts GTK geometry to the runner's
      // default when resizable(false) is applied. Keep Linux programmatic
      // resizing functional; the pinned runner default is patched in CI.
      if (!Platform.isLinux) await windowManager.setResizable(false);
      await windowManager.focus();
    });
  }

  Future<void> setSurface(QingfanController controller) async {
    // Make the native GTK window temporarily resizable before a
    // programmatic mode change; resizing nonresizable windows is
    // window-manager dependent and may silently keep the old dimensions.
    await windowManager.setResizable(true);
    await windowManager.setSize(sizeFor(controller.mode, controller.panel));
    if (!Platform.isLinux) await windowManager.setResizable(false);
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
