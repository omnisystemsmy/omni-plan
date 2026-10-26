import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';

/// Icon + label button with no card. Copied from the Omni Tools tile (same
/// sizes, type and press feedback) minus the Pro badge, so quick actions and
/// the Templates directory look identical to the Tools screens.
class OmniToolTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Lines of label before it is cut off. Omni Tools uses 2; document names
  /// are longer, so the template grids allow 3.
  final int maxLines;

  const OmniToolTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.maxLines = 2,
  });

  /// Same grid with slightly taller cells, for three-line labels.
  static const SliverGridDelegate tallGridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 0,
        childAspectRatio: 0.78,
      );

  /// Grid shape shared by every directory-style page.
  static const SliverGridDelegate gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 0,
        childAspectRatio: 0.9,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: OmniPressScale(
        scale: 0.94,
        child: InkWell(
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              children: [
                SizedBox(
                  width: 58,
                  height: 46,
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
