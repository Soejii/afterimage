import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Draws the four bracket corners from the application icon around its child.
///
/// This is the one piece of brand language that also does a job: while a batch
/// is running the whole progress panel sits inside a viewfinder, so "Afterimage
/// is capturing right now" reads from across the room rather than from a small
/// text label. Kept to plain strokes, with no glow or shadow, because this
/// window is on screen while the machine is also running the game and encoding
/// video.
class ViewfinderFrame extends StatelessWidget {
  const ViewfinderFrame({
    super.key,
    required this.child,
    this.color = AfterimageTheme.recording,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ViewfinderPainter(color: color),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Corner arms scale with the panel but stay within a readable range, so a
    // narrow window does not end up with brackets that meet in the middle.
    final arm = (size.shortestSide * 0.12).clamp(14.0, 34.0);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const inset = 1.0;
    const left = inset;
    const top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;
    const radius = 8.0;

    void corner(Offset origin, double dx, double dy) {
      final path = Path()
        ..moveTo(origin.dx + dx * arm, origin.dy)
        ..lineTo(origin.dx + dx * radius, origin.dy)
        ..quadraticBezierTo(
          origin.dx,
          origin.dy,
          origin.dx,
          origin.dy + dy * radius,
        )
        ..lineTo(origin.dx, origin.dy + dy * arm);
      canvas.drawPath(path, stroke);
    }

    corner(const Offset(left, top), 1, 1);
    corner(Offset(right, top), -1, 1);
    corner(Offset(left, bottom), 1, -1);
    corner(Offset(right, bottom), -1, -1);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The icon's orange record dot, pulsing while a recording is in progress.
class RecordDot extends StatefulWidget {
  const RecordDot({super.key, this.size = 12, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<RecordDot> createState() => _RecordDotState();
}

class _RecordDotState extends State<RecordDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RecordDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = widget.animate ? 0.45 + (_controller.value * 0.55) : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AfterimageTheme.recording.withValues(alpha: alpha),
          ),
        );
      },
    );
  }
}
