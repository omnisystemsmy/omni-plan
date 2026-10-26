import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// Full-screen "welcome to Pro" moment with falling confetti, the same as in
/// Omni Tools.
Future<void> showProCelebration(BuildContext context) {
  HapticFeedback.heavyImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const _ProCelebration(),
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _ProCelebration extends StatefulWidget {
  const _ProCelebration();

  @override
  State<_ProCelebration> createState() => _ProCelebrationState();
}

class _ProCelebrationState extends State<_ProCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  final List<_Piece> _pieces = _makePieces();

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (!reduce)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) =>
                      CustomPaint(painter: _ConfettiPainter(_pieces, _c.value)),
                ),
              ),
            ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: OmniDesignTokens.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "You're Pro now!",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thank you for supporting Omni Plan. Your Pro features '
                      'are now unlocked.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Let's go"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Piece {
  final double x, delay, speed, size, spin, sway;
  final Color color;
  const _Piece(
    this.x,
    this.delay,
    this.speed,
    this.size,
    this.spin,
    this.sway,
    this.color,
  );
}

List<_Piece> _makePieces() {
  final r = math.Random(7);
  const colors = [
    OmniDesignTokens.primary,
    OmniDesignTokens.accentAmber,
    Color(0xFFE91E63),
    Color(0xFF7C4DFF),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
  ];
  return List.generate(
    70,
    (_) => _Piece(
      r.nextDouble(),
      r.nextDouble() * 0.35,
      0.7 + r.nextDouble() * 0.6,
      6 + r.nextDouble() * 7,
      (r.nextDouble() - 0.5) * 14,
      r.nextDouble() * 0.06 + 0.02,
      colors[r.nextInt(colors.length)],
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + (size.height + 60) * math.pow(local, 1.15) * p.speed;
      if (y > size.height + 20) continue;
      final x =
          p.x * size.width +
          math.sin(local * 9 + p.x * 6) * size.width * p.sway;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - local * 0.4).clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.55,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Shows the Pro celebration whenever a purchase is confirmed, wherever the
/// person happens to be in the app.
class ProCelebrationHost extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<int> celebrations;
  final Widget child;

  const ProCelebrationHost({
    super.key,
    required this.navigatorKey,
    required this.celebrations,
    required this.child,
  });

  @override
  State<ProCelebrationHost> createState() => _ProCelebrationHostState();
}

class _ProCelebrationHostState extends State<ProCelebrationHost> {
  @override
  void initState() {
    super.initState();
    widget.celebrations.addListener(_celebrate);
  }

  @override
  void dispose() {
    widget.celebrations.removeListener(_celebrate);
    super.dispose();
  }

  void _celebrate() {
    final ctx = widget.navigatorKey.currentState?.overlay?.context;
    if (ctx != null) showProCelebration(ctx);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
