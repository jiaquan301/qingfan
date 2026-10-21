import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/qingfan_controller.dart';

const _ink = Color(0xFF173F34);
const _accent = Color(0xFF38735E);
const _muted = Color(0xFF80978B);
const _surface = Color(0xFFF9FBF8);

/// A restrained, single-object timepiece. Only frequent actions are visible.
/// Ring/unused dial space initiates native OS dragging; the centre is tap-only.
class CrystalClock extends StatefulWidget {
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
  State<CrystalClock> createState() => _CrystalClockState();
}

class _CrystalClockState extends State<CrystalClock> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final mini = c.mode == ClockMode.mini && c.panel == OpenPanel.none;
    return LayoutBuilder(builder: (context, constraints) {
      final diameter = math.max(
        1.0,
        math.min(
          constraints.maxWidth - (mini ? 3 : 24),
          constraints.maxHeight - (mini ? 3 : 24),
        ),
      );
      return Center(
        child: SizedBox.square(
          dimension: diameter,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimepiecePainter(
                      progress: c.progress,
                      opacity: c.glassOpacity,
                      phase: c.engine.phase.name,
                      mini: mini,
                    ),
                  ),
                ),
                // Inactive dial material is a drag surface. Keeping it BELOW
                // the centre and controls makes focus and drag independent.
                Positioned.fill(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      key: const Key('clockDragSurface'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => widget.onDrag(),
                      onSecondaryTapUp: (_) => widget.onMore(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (!mini)
                  Positioned(
                    top: diameter * .265,
                    child: Text(
                      c.phaseLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _muted,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                Center(
                  child: Semantics(
                    button: true,
                    label: c.engine.isRunning ? '暂停专注' : '开始或继续专注',
                    child: Tooltip(
                      message: c.engine.isRunning ? '点击暂停' : '点击开始 / 继续',
                      child: GestureDetector(
                        key: const Key('clockCenter'),
                        behavior: HitTestBehavior.opaque,
                        onTap: c.toggleFocus,
                        child: SizedBox(
                          width: diameter * (mini ? .62 : .73),
                          height: diameter * (mini ? .52 : .36),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c.formattedTime,
                                maxLines: 1,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: mini ? 19 : 60,
                                  height: 1.03,
                                  letterSpacing: mini ? -.8 : -2.6,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  fontFamily: 'Noto Sans',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!mini) ...[
                                const SizedBox(height: 12),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 210),
                                  child: Text(
                                    c.taskTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: _accent,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: .3,
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
                    bottom: diameter * .215,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(4, (index) {
                        final done = index < c.engine.completedRounds % 4;
                        return Container(
                          height: 4,
                          width: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 5.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? _accent : const Color(0xFFBED5CA),
                          ),
                        );
                      }),
                    ),
                  ),
                if (!mini) ...[
                  Positioned(
                    left: diameter * .155,
                    top: diameter * .115,
                    child: _QuietAction(
                      label: '任务清单',
                      icon: Icons.format_list_bulleted_rounded,
                      onTap: widget.onTasks,
                    ),
                  ),
                  Positioned(
                    right: diameter * .155,
                    top: diameter * .115,
                    child: _QuietAction(
                      label: '迷你模式',
                      icon: Icons.open_in_full_rounded,
                      onTap: widget.onMode,
                    ),
                  ),
                  Positioned(
                    bottom: diameter * .075,
                    child: _QuietAction(
                      label: '更多：设置、重置',
                      icon: Icons.more_horiz_rounded,
                      onTap: widget.onMore,
                      small: true,
                    ),
                  ),
                ] else
                  Positioned(
                    top: 4,
                    right: 5,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 135),
                        child: _QuietAction(
                          label: '展开时钟',
                          icon: Icons.open_in_full_rounded,
                          onTap: widget.onMode,
                          small: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _QuietAction extends StatelessWidget {
  const _QuietAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.small = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(
          foregroundColor: _accent.withValues(alpha: .88),
          hoverColor: const Color(0x253E7560),
          highlightColor: const Color(0x183E7560),
        ),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: small ? 32 : 40,
          height: small ? 32 : 40,
        ),
        icon: Icon(icon, size: small ? 17 : 19),
      );
}

/// Matte-ivory crystal and machined fine ring, not a large flat gray disc.
/// All pixels outside the circular painter remain fully transparent.
class _TimepiecePainter extends CustomPainter {
  const _TimepiecePainter({
    required this.progress,
    required this.opacity,
    required this.phase,
    required this.mini,
  });

  final double progress;
  final double opacity;
  final String phase;
  final bool mini;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - (mini ? 1.8 : 3.0);
    final outer = Rect.fromCircle(center: center, radius: r);
    final fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.33, -.42),
        radius: 1.24,
        colors: [
          Colors.white.withValues(alpha: opacity),
          _surface.withValues(alpha: opacity * .96),
          const Color(0xFFEAF2ED).withValues(alpha: opacity * .93),
        ],
        stops: const [0, .58, 1],
      ).createShader(outer);
    canvas.drawCircle(center, r, fill);

    // One continuous polished bezel instead of several competing rings.
    canvas.drawCircle(
      center,
      r - .95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? .9 : 1.15
        ..color = Colors.white.withValues(alpha: .86),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - (mini ? 2 : 3)),
      -math.pi * .89,
      math.pi * .48,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? .9 : 1.45
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .87),
    );

    final ringR = r * (mini ? .80 : .775);
    final thickness = mini ? 2.3 : 3.2;
    final ringRect = Rect.fromCircle(center: center, radius: ringR);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = const Color(0xFFD6E7DC).withValues(alpha: .75),
    );
    if (progress > 0.0001) {
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        progress.clamp(0.0, 1.0) * math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..color = phase == 'focus' ? _accent : const Color(0xFF668B94),
      );
    }
  }

  @override
  bool shouldRepaint(_TimepiecePainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.phase != phase ||
      old.mini != mini;
}
