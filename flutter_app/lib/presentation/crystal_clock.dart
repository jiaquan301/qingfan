import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/qingfan_controller.dart';
import '../domain/focus_engine.dart';

const _ink = Color(0xFF173F34);
const _accent = Color(0xFF38735E);
const _surface = Color(0xFFF9FBF8);

/// Always the same 104 logical-pixel circular timepiece, on every surface.
/// At rest it paints only the remaining time and the progress ring.
/// Standard play/pause, tasks and menu controls fade in on hover.
class CrystalClock extends StatefulWidget {
  const CrystalClock({
    super.key,
    required this.controller,
    required this.onTasks,
    required this.onDrag,
    required this.onMore,
  });

  final QingfanController controller;
  final VoidCallback onTasks;
  final VoidCallback onDrag;
  final VoidCallback onMore;

  @override
  State<CrystalClock> createState() => _CrystalClockState();
}

class _CrystalClockState extends State<CrystalClock> {
  bool _hovered = false;

  // Keep the timepiece reactive even when embedded without a parent
  // AnimatedBuilder (widget previews and isolated tool windows).
  void _modelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_modelChanged);
  }

  @override
  void didUpdateWidget(covariant CrystalClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_modelChanged);
      widget.controller.addListener(_modelChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_modelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final rest = c.engine.phase == FocusPhase.rest;
    final running = c.engine.runState == RunState.running;
    return Center(
      child: SizedBox(
        key: const Key('singleDial'),
        width: 104,
        height: 104,
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
                    rest: rest,
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('clockDragSurface'),
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => widget.onDrag(),
                  onSecondaryTapUp: (_) => widget.onMore(),
                ),
              ),
              Semantics(
                button: !rest,
                label: rest ? '休息自动倒计时' : (running ? '暂停专注' : '开始专注'),
                child: GestureDetector(
                  key: const Key('clockCenter'),
                  behavior: HitTestBehavior.opaque,
                  onTap: rest ? null : c.toggleFocus,
                  child: SizedBox(
                    width: 84,
                    height: 48,
                    child: Center(
                      child: Text(
                        c.formattedTime,
                        maxLines: 1,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 23,
                          height: 1,
                          letterSpacing: -1.15,
                          fontFamily: 'Noto Sans',
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_hovered) ...[
                Positioned(
                  left: 8,
                  top: 6,
                  child: _TinyAction(
                    tooltip: '任务清单',
                    icon: Icons.format_list_bulleted_rounded,
                    onPressed: widget.onTasks,
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 6,
                  child: _TinyAction(
                    tooltip: '更多',
                    icon: Icons.more_horiz_rounded,
                    onPressed: widget.onMore,
                  ),
                ),
                if (!rest)
                  Positioned(
                    bottom: 4,
                    child: _TinyAction(
                      key: const Key('focusToggleIcon'),
                      tooltip: running ? '暂停专注' : '开始或继续专注',
                      icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      onPressed: c.toggleFocus,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 15),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 27, height: 24),
    style: IconButton.styleFrom(
      foregroundColor: _accent,
      hoverColor: const Color(0x293E7560),
    ),
  );
}

class _TimepiecePainter extends CustomPainter {
  const _TimepiecePainter({
    required this.progress,
    required this.opacity,
    required this.rest,
  });
  final double progress;
  final double opacity;
  final bool rest;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1.6;
    final outer = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center, r,
      Paint()..shader = RadialGradient(
        center: const Alignment(-.33, -.42),
        radius: 1.24,
        colors: [
          Colors.white.withValues(alpha: opacity),
          _surface.withValues(alpha: opacity * .96),
          const Color(0xFFEAF2ED).withValues(alpha: opacity * .93),
        ],
        stops: const [0, .58, 1],
      ).createShader(outer),
    );
    canvas.drawCircle(
      center, r - .9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = Colors.white.withValues(alpha: .86),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 2),
      -math.pi * .89, math.pi * .48, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .87),
    );
    final ringRect = Rect.fromCircle(center: center, radius: r * .80);
    canvas.drawCircle(
      center, r * .80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..color = const Color(0xFFD6E7DC).withValues(alpha: .75),
    );
    if (progress > 0.0001) {
      canvas.drawArc(
        ringRect, -math.pi / 2,
        progress.clamp(0.0, 1.0) * math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.3
          ..strokeCap = StrokeCap.round
          ..color = rest ? const Color(0xFF668B94) : _accent,
      );
    }
  }

  @override
  bool shouldRepaint(_TimepiecePainter old) =>
      old.progress != progress || old.opacity != opacity || old.rest != rest;
}
