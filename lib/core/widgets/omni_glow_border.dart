import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A thin outline in the four colours of the Omni logo around a pill-shaped
/// field. The colours travel slowly around the outline. There is no glow.
class OmniGlowBorder extends StatefulWidget {
  final Widget child;

  const OmniGlowBorder({super.key, required this.child});

  static const _colors = <Color>[
    Color(0xFFF2616A), // coral
    Color(0xFFF8C230), // yellow
    Color(0xFF3B9BF2), // blue
    Color(0xFF1FC6C1), // teal
    Color(0xFFF2616A), // back to coral so the sweep joins without a seam
  ];

  @override
  State<OmniGlowBorder> createState() => _OmniGlowBorderState();
}

class _OmniGlowBorderState extends State<OmniGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _OutlinePainter(_spin),
    child: widget.child,
  );
}

class _OutlinePainter extends CustomPainter {
  final Animation<double> turn;

  _OutlinePainter(this.turn) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(1),
        Radius.circular(size.height / 2),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(
          colors: OmniGlowBorder._colors,
          transform: GradientRotation(turn.value * 2 * math.pi),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter old) => old.turn != turn;
}
