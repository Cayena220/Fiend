import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fiend's mark: a watching eye with a slit pupil.
class Sigil extends StatelessWidget {
  const Sigil({super.key, this.size = 28, required this.color, this.glow = true});
  final double size;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size * 0.72),
        painter: _SigilPainter(color, glow),
      );
}

class _SigilPainter extends CustomPainter {
  _SigilPainter(this.color, this.glow);
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final eye = Path()
      ..moveTo(0.04 * w, 0.5 * h)
      ..quadraticBezierTo(0.5 * w, -0.18 * h, 0.96 * w, 0.5 * h)
      ..quadraticBezierTo(0.5 * w, 1.18 * h, 0.04 * w, 0.5 * h)
      ..close();
    final pupil = Path()
      ..moveTo(0.5 * w, 0.14 * h)
      ..quadraticBezierTo(0.64 * w, 0.5 * h, 0.5 * w, 0.86 * h)
      ..quadraticBezierTo(0.36 * w, 0.5 * h, 0.5 * w, 0.14 * h)
      ..close();

    if (glow) {
      canvas.drawPath(
        pupil,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(
      eye,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.075).clamp(1.4, 4.0)
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(pupil, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SigilPainter old) => old.color != color || old.glow != glow;
}

/// Ring gauge used for the health score.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.value, required this.color, required this.track, this.size = 168, this.stroke = 12, this.child});
  final double value;
  final Color color;
  final Color track;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0, 1), color, track, stroke),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2 + 6);
    const start = -math.pi * 1.25;
    const sweep = math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, start, sweep, false, base..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      r,
      start,
      sweep * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawArc(r, start, sweep * value, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}
