import 'package:flutter/material.dart';

/// Omni Plan logo, same idea as `DocsLogo` in Omni Docs: a transparent
/// wordmark that switches between the black and the white artwork with the
/// theme, so it is always readable.
///
/// Every place that draws the brand goes through here, so a future logo
/// change is a matter of swapping the two assets.
class PlanLogo extends StatelessWidget {
  static const String lightAsset = 'assets/images/omni plan logo (black) no bg.png';
  static const String darkAsset = 'assets/images/omni plan logo (white) no bg.png';

  final double height;

  const PlanLogo({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      child: Image.asset(
        isDark ? darkAsset : lightAsset,
        fit: BoxFit.contain,
        semanticLabel: 'Omni Plan',
      ),
    );
  }
}

/// The logo as shown in the app bar.
class PlanBrandAppBar extends StatelessWidget {
  const PlanBrandAppBar({super.key});

  @override
  Widget build(BuildContext context) => const PlanLogo();
}
