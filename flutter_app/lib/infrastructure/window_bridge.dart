import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../application/qingfan_controller.dart';

/// One and only one native window. All UI modes are Flutter views of it.
class DesktopWindowBridge {
  static const dialSize = Size(104, 104);
  // Win32 minimum frameless HWND width; circular painted dial stays 104px.
  static const windowsDialWindowSize = Size(136, 104);
  Size get effectiveDialWindowSize =>
      Platform.isWindows ? windowsDialWindowSize : dialSize;
  // Fixed 112px clock rail plus a 410px task/settings workspace.
  static const panelSize = Size(522, 510);

  bool get likelyWayland =>
      Platform.isLinux &&
      Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';

  Size sizeFor(OpenPanel panel) =>
      panel == OpenPanel.none ? effectiveDialWindowSize : panelSize;

  Future<void> prepare() => windowManager.ensureInitialized();

  Future<void> showInitial(QingfanController controller) async {
    final options = WindowOptions(
      size: sizeFor(controller.panel),
      minimumSize: effectiveDialWindowSize,
      center: true,
      // The dial is a frameless translucent surface on every desktop OS.
      // Expanded panels paint their own opaque porcelain background. Linux
      // also needs the RGBA GTK runner patch for true corner transparency.
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setTitle('青番');
      // Flutter's default Linux runner starts at 1280x720. Do not freeze
      // that initial geometry before requesting the final 104x104 size.
      await windowManager.setResizable(true);
      await windowManager.setSize(sizeFor(controller.panel));
      await applyTopmost(controller);
      await windowManager.show();
      await windowManager.setSize(sizeFor(controller.panel));
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
    await windowManager.setSize(sizeFor(controller.panel));
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

  Future<void> close() async {
    // GTK's close-request handler can race the implicit Flutter view removal
    // during shutdown. Explicit destroy avoids reentering close-request.
    if (Platform.isLinux) {
      await windowManager.destroy();
    } else {
      await windowManager.close();
    }
  }
}
