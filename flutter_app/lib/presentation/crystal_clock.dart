import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/qingfan_controller.dart';

const _ink = Color(0xFF153E31);
const _accent = Color(0xFF337259);
const _mist = Color(0xFF81978B);
const _glass = Color(0xFFF7FBF9);

/// Primary clock surface. The centre is the only start/pause target.
class CrystalClock extends StatelessWidget {
  const CrystalClock({
    super.key,
    required this.controller,
    required this.onTasks,
    required this.onSettings,
    required this.onMode,
    required this.onReset,
    required this.onDrag,
    required this.onMore,
  });

  final QingfanController controller;
  final VoidCallback onTasks;
  final VoidCallback onSettings;
  final VoidCallback onMode;
  final VoidCallback onReset;
  final VoidCallback onDrag;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final mini = controller.mode == ClockMode.mini &&
        controller.panel == OpenPanel.none;
    return LayoutBuilder(builder: (context, constraints) {
      final diameter = math.min(constraints.maxWidth - (mini ? 2 : 20),
          constraints.maxHeight - (mini ? 2 : 20));
      return Center(
        child: SizedBox.square(
          dimension: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CrystalPainter(
                    progress: controller.progress,
                    opacity: controller.glassOpacity,
                    phase: controller.engine.phase.name,
                    running: controller.engine.isRunning,
                    mini: mini,
                  ),
                ),
              ),
              // Blank areas of the dial are the native window drag surface.
              // Foreground actions and the centre timer tap sit above it in
              // the Stack's hit-test order, so dragging cannot toggle focus.
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    key: const Key('clockDragSurface'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => onDrag(),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (!mini)
                Positioned(
                  top: diameter * .24,
                  child: Text(
                    controller.phaseLabel,
                    style: const TextStyle(
                      color: _mist,
                      fontSize: 13,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Center(
                child: Semantics(
                  button: true,
                  label: controller.engine.isRunning
                      ? '暂停专注'
                      : '开始或继续专注',
                  child: Tooltip(
                    message: controller.engine.isRunning ? '点击暂停' : '点击开始 / 继续',
                    child: GestureDetector(
                      key: const Key('clockCenter'),
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.toggleFocus,
                      child: SizedBox(
                        width: mini ? diameter * .64 : diameter * .75,
                        height: mini ? diameter * .68 : diameter * .42,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              controller.formattedTime,
                              maxLines: 1,
                              style: TextStyle(
                                color: _ink,
                                fontSize: mini ? 19 : 64,
                                height: 1.03,
                                letterSpacing: mini ? -1 : -2.7,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!mini) ...[
                              const SizedBox(height: 9),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  controller.taskTitle,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: _accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!mini)
                Positioned(
                  bottom: diameter * .19,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (index) {
                      final complete = index < controller.engine.completedRounds % 4;
                      return Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: complete ? _accent : const Color(0xFFCEE1D5),
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  ),
                ),
              if (!mini) ...[
                Positioned(
                  left: diameter * .07,
                  top: diameter * .075,
                  child: _OrbIcon(Icons.format_list_bulleted_rounded, '任务清单', onTasks),
                ),
                Positioned(
                  right: diameter * .07,
                  top: diameter * .075,
                  child: _OrbIcon(Icons.close_fullscreen_rounded, '迷你模式', onMode),
                ),
                Positioned(
                  left: diameter * .07,
                  bottom: diameter * .075,
                  child: _OrbIcon(Icons.settings_outlined, '设置', onSettings),
                ),
                Positioned(
                  right: diameter * .07,
                  bottom: diameter * .075,
                  child: _OrbIcon(Icons.refresh_rounded, '重置计时', onReset),
                ),
                Positioned(
                  bottom: 0,
                  child: _WindowDragHandle(onDrag: onDrag),
                ),
              ] else ...[
                Positioned(
                  top: 0,
                  right: 0,
                  child: _OrbIcon(Icons.open_in_full_rounded, '展开时钟', onMode,
                      mini: true),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: _WindowDragHandle(onDrag: onDrag, mini: true),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: _OrbIcon(Icons.more_horiz_rounded, '更多', onMore,
                      mini: true),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

/// Starts an OS-level window move while the pointer is still pressed and
/// moving. A normal IconButton.onPressed fires on mouse-up, too late for
/// gtk_window_begin_move_drag on Linux, which explains the broken handle.
class _WindowDragHandle extends StatelessWidget {
  const _WindowDragHandle({required this.onDrag, this.mini = false});

  final VoidCallback onDrag;
  final bool mini;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '按住并拖动窗口',
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            key: Key(mini ? 'miniDragHandle' : 'fullDragHandle'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDrag(),
            child: SizedBox(
              height: mini ? 28 : 40,
              width: mini ? 28 : 40,
              child: Icon(
                Icons.drag_indicator_rounded,
                size: mini ? 15 : 20,
                color: _accent,
              ),
            ),
          ),
        ),
      );
}

class _OrbIcon extends StatelessWidget {
  const _OrbIcon(this.icon, this.tooltip, this.callback, {this.mini = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback callback;
  final bool mini;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            type: MaterialType.transparency,
            child: IconButton(
              tooltip: tooltip,
              splashRadius: mini ? 15 : 20,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: mini ? 28 : 40,
                height: mini ? 28 : 40,
              ),
              icon: Icon(icon, size: mini ? 15 : 20, color: _accent),
              onPressed: callback,
            ),
          ),
        ),
      );
}

class _CrystalPainter extends CustomPainter {
  const _CrystalPainter({
    required this.progress,
    required this.opacity,
    required this.phase,
    required this.running,
    required this.mini,
  });

  final double progress;
  final double opacity;
  final String phase;
  final bool running;
  final bool mini;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - (mini ? 2 : 5);
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.32, -.58),
          radius: 1.26,
          colors: [
            Colors.white.withValues(alpha: opacity),
            _glass.withValues(alpha: opacity * .97),
            const Color(0xFFE4EFE8).withValues(alpha: opacity * .90),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius - 0.8,
      Paint()
        ..color = Colors.white.withValues(alpha: .67)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final ringRadius = radius * (mini ? .82 : .76);
    final track = Paint()
      ..color = const Color(0xFFCBDED1).withValues(alpha: .64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = mini ? 3.4 : 5.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, ringRadius, track);
    final progressPaint = Paint()
      ..color = phase == 'focus' ? _accent : const Color(0xFF4C7B87)
      ..style = PaintingStyle.stroke
      ..strokeWidth = mini ? 3.4 : 5.5
      ..strokeCap = StrokeCap.round;
    if (progress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1),
        false,
        progressPaint,
      );
    }
    // A single restrained specular highlight gives a crafted glass edge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 3),
      -math.pi * .82,
      math.pi * .45,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .68)
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 1 : 2,
    );
  }

  @override
  bool shouldRepaint(_CrystalPainter previous) =>
      previous.progress != progress ||
      previous.opacity != opacity ||
      previous.phase != phase ||
      previous.running != running ||
      previous.mini != mini;
}
